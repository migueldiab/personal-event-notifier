# frozen_string_literal: true

require "httparty"
require "json"
require "uri"

module WeeklyLocalEvents
  # OAuth client for the Eventbrite API v3.
  #
  # Eventbrite supports two ways to authenticate an API request:
  #   1. A private token generated on the account's API Keys page.
  #   2. The OAuth 2.0 authorization-code flow (API key + client secret).
  #
  # Credentials are read from the environment by .from_env; no secrets are
  # stored in source control.
  class EventbriteClient
    class Error < StandardError; end
    class MissingCredentialsError < Error; end
    class AuthenticationError < Error; end

    TOKEN_URL = "https://www.eventbrite.com/oauth/token"
    AUTHORIZE_URL = "https://www.eventbrite.com/oauth/authorize"
    API_BASE_URL = "https://www.eventbriteapi.com"

    attr_reader :client_id, :client_secret, :redirect_uri, :private_token

    # Build a client from EVENTBRITE_* environment variables.
    #
    # @return [EventbriteClient]
    def self.from_env
      new(
        client_id: ENV.fetch("EVENTBRITE_CLIENT_ID", nil),
        client_secret: ENV.fetch("EVENTBRITE_CLIENT_SECRET", nil),
        redirect_uri: ENV.fetch("EVENTBRITE_REDIRECT_URI", nil),
        private_token: ENV.fetch("EVENTBRITE_PRIVATE_TOKEN", nil)
      )
    end

    # @param client_id [String, nil] the Eventbrite API key
    # @param client_secret [String, nil] the OAuth client secret
    # @param redirect_uri [String, nil] registered OAuth redirect URI
    # @param private_token [String, nil] personal token from the API Keys page
    def initialize(client_id: nil, client_secret: nil, redirect_uri: nil, private_token: nil)
      @client_id = client_id
      @client_secret = client_secret
      @redirect_uri = redirect_uri
      @private_token = private_token
    end

    # Whether any usable credentials are configured.
    #
    # @return [Boolean]
    def configured?
      !private_token.to_s.strip.empty? ||
        (!client_id.to_s.strip.empty? && !client_secret.to_s.strip.empty?)
    end

    # URL used to start the server-side authorization-code flow.
    #
    # @param state [String, nil] opaque value returned to the redirect URI
    # @return [String]
    def authorization_url(state: nil)
      params = {
        response_type: "code",
        client_id: client_id,
        redirect_uri: redirect_uri
      }
      params[:state] = state unless state.nil?
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    # Exchange an authorization code for a private token.
    #
    # @param code [String] code received on the redirect URI
    # @param redirect_uri [String, nil] override for the registered redirect URI
    # @return [String] the private token
    # @raise [MissingCredentialsError] when credentials or code are absent
    # @raise [AuthenticationError] when Eventbrite rejects the exchange
    def exchange_code(code, redirect_uri: self.redirect_uri)
      raise MissingCredentialsError, "Client ID, client secret and authorization code are required" if
        missing_oauth_credentials?(code)

      response = HTTParty.post(
        TOKEN_URL,
        headers: { "Content-Type" => "application/x-www-form-urlencoded" },
        body: URI.encode_www_form(
          grant_type: "authorization_code",
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: redirect_uri
        )
      )
      token_from(response)
    end

    # Token used to authenticate API requests.
    #
    # @return [String, nil]
    def access_token
      private_token
    end

    # Fetch a single event by ID.
    #
    # @param event_id [String, Integer] Eventbrite event ID
    # @return [Hash] parsed API response
    def event(event_id)
      get("/v3/events/#{event_id}/")
    end

    # Perform an authenticated GET against the Eventbrite API.
    #
    # @param path [String] path beginning with /v3/
    # @param query [Hash] query parameters
    # @return [Hash] parsed API response
    # @raise [AuthenticationError] on 401/403
    # @raise [Error] on any other failure
    def get(path, query: {})
      response = get_response(path, query: query)
      raise AuthenticationError, "Eventbrite API returned #{response.code}" if [401, 403].include?(response.code)
      raise Error, "Eventbrite API returned #{response.code}: #{response.body}" unless response.success?

      response.parsed_response
    end

    # Perform an authenticated GET and return the raw response so callers can
    # inspect status codes and headers (needed for 429 backoff and retries).
    #
    # @param path [String] path beginning with /v3/
    # @param query [Hash] query parameters
    # @return [HTTParty::Response] unmodified HTTP response
    def get_response(path, query: {})
      HTTParty.get(
        "#{API_BASE_URL}#{path}",
        headers: { "Authorization" => "Bearer #{access_token}" },
        query: query
      )
    end

    private

    def missing_oauth_credentials?(code)
      client_id.to_s.strip.empty? || client_secret.to_s.strip.empty? || code.to_s.strip.empty?
    end

    def token_from(response)
      body = response.parsed_response
      token = body.is_a?(Hash) ? body["access_token"] : nil
      return token if response.success? && !token.to_s.empty?

      message = "Eventbrite token request failed (#{response.code})"
      detail = body.is_a?(Hash) ? (body["error_description"] || body["error"]) : nil
      message += ": #{detail}" if detail
      message += ": response did not include access_token" if response.success?
      raise AuthenticationError, message
    end
  end
end
