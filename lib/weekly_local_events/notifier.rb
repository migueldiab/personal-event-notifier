# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "weekly_local_events/aggregator"

module WeeklyLocalEvents
  # Telegram API response wrapper.
  #
  # Usage:
  #   response = TelegramResponse.new(success: true, message_id: 12345)
  #   response.success?  # => true
  #   response.message_id  # => 12345
  class TelegramResponse
    attr_reader :success, :message_id, :error, :api_error

    def initialize(success:, message_id: nil, error: nil, api_error: nil)
      @success = success
      @message_id = message_id
      @error = error
      @api_error = api_error
    end

    def success?
      @success
    end

    def to_h
      { success: success, message_id: message_id, error: error, api_error: api_error }
    end

    def to_s
      return "TelegramResponse(OK: message_id=#{message_id})" if success?
      if error
        "TelegramResponse(FAILED: #{error})"
      elsif api_error && api_error.is_a?(Hash)
        "TelegramResponse(FAILED: #{api_error['description'] || api_error['error_code'] || 'API error'})"
      else
        "TelegramResponse(FAILED: #{api_error})"
      end
    end
  end

  # Notifier class that sends notifications via Telegram.
  #
  # Supports Markdown and HTML parse modes, respects Telegram's 4096
  # character limit, handles rate limiting, and provides formatted
  # event and summary messages.
  #
  # Usage:
  #   notifier = Notifier.new(config)
  #   notifier.send_events(events)
  #   notifier.send_with_html("<b>Test</b>")
  #
  class Notifier
    # Maximum message length allowed by Telegram API.
    MAX_MESSAGE_LENGTH = 4096

    # Rate limit: Telegram allows ~30 messages/second for bots.
    # We use a conservative 30-second minimum between sends.
    MIN_SEND_INTERVAL = 30.0

    # Rate limit: Telegram allows ~20 messages per minute for groups.
    MAX_MESSAGES_PER_MINUTE = 2 

    attr_reader :config, :api_base, :last_send_at, :recent_message_count, :recent_message_times

    def initialize(config)
      @config = config
      @api_base = config.telegram_bot_token ? "https://api.telegram.org/bot#{config.telegram_bot_token}" : "https://api.telegram.org/bot"
      @last_send_at = nil
      @recent_message_count = 0
      @recent_message_times = []
      @mutex = Mutex.new
    end

    # Send a single message via Telegram.
    #
    # @param message [String] the message text
    # @param parse_mode [String, nil] "MarkdownV2", "HTML", or nil
    # @return [TelegramResponse]
    def send_message(message, parse_mode: nil)
      return TelegramResponse.new(success: false, error: "No message provided") if message.to_s.strip.empty?

      truncated = truncate_message(message)

      @mutex.synchronize do
        check_rate_limit!
        @recent_message_times << Time.now
        @recent_message_count += 1
      end

      send_telegram_api(truncated, parse_mode: parse_mode)
    end

    # Format events into a Telegram-friendly message and send them.
    #
    # Groups events by category and includes a summary line.
    #
    # @param events [Array<Event>]
    # @return [TelegramResponse]
    def send_events(events)
      return TelegramResponse.new(success: false, error: "No events provided") if events.empty?

      formatted = format_events(events)
      summary = format_summary_for_events(events)

      message = "#{formatted}\n\n#{summary}"
      send_with_markdown(message)
    end

    # Format a list of events into a Telegram-friendly text block.
    #
    # Groups events by category with emoji headers.
    #
    # @param events [Array<Event>]
    # @return [String] formatted text
    def format_events(events)
      return "No events found." if events.empty?

      lines = ["📅 *Weekly Austin Events*", "📆 *Next 7 days*", ""]

      grouped = events.group_by { |e| normalize_category(e.category) }

      category_order = ["Music", "Comedy", "Festival", "Sports", "Art", "Food & Drink", "Market", "Education", "Theater", "Family", "Nightlife", "Outdoor", "Religious", "Politics", "Technology", "Other"]

      category_order.each do |cat|
        cat_events = grouped[cat]
        next unless cat_events

        lines << "🎵 *#{cat}*" if cat == "Music"
        lines << "🎭 *#{cat}* " if cat == "Comedy"
        lines << "🎪 *#{cat}* " if cat == "Festival"
        lines << "⚽ *#{cat}* " if cat == "Sports"
        lines << "🎨 *#{cat}* " if cat == "Art"
        lines << "🍽️ *#{cat}* " if cat == "Food & Drink"
        lines << "🏪 *#{cat}* " if cat == "Market"
        lines << "📚 *#{cat}* " if cat == "Education"
        lines << "🎭 *#{cat}* " if cat == "Theater"
        lines << "👨‍👩‍👧 *#{cat}* " if cat == "Family"
        lines << "🌙 *#{cat}* " if cat == "Nightlife"
        lines << "🌲 *#{cat}* " if cat == "Outdoor"
        lines << "⛪ *#{cat}* " if cat == "Religious"
        lines << "🗳️ *#{cat}* " if cat == "Politics"
        lines << "💻 *#{cat}* " if cat == "Technology"
        lines << "📋 *#{cat}* " if cat == "Other"

        cat_events.each do |event|
          price = event.price_range
          price_str = price.empty? ? "Free" : price
          lines << "- *#{event.title}* - #{event.venue&.name || 'Unknown'} - #{price_str}"
        end
        lines << ""
      end

      lines.join("\n")
    end

    # Format a summary hash into a Telegram-friendly text block.
    #
    # @param summary [Hash] keys: total, free_count, paid_count, categories, etc.
    # @return [String] formatted summary text
    def format_summary(summary)
      return "No summary available." unless summary && summary.is_a?(Hash)

      total = summary[:total] || summary["total"] || 0
      free_count = summary[:free_count] || summary["free_count"] || 0
      paid_count = summary[:paid_count] || summary["paid_count"] || (total - free_count)
      categories = summary[:categories] || summary["categories"] || []
      sources = summary[:sources] || summary["sources"] || []

      lines = ["📊 *Summary*", ""]
      lines << "- *Total events*: #{total}"
      lines << "- *Free events*: #{free_count}"
      lines << "- *Paid events*: #{paid_count}"
      lines << ""

      unless categories.empty?
        lines << "📂 *By Category*:"
        categories.each do |cat, count|
          lines << "  - #{cat}: #{count}"
        end
        lines << ""
      end

      unless sources.empty?
        lines << "📡 *By Source*:"
        sources.each do |src, count|
          lines << "  - #{src}: #{count}"
        end
        lines << ""
      end

      lines.join("\n")
    end

    # Format a summary from events (shortcut for format_summary).
    #
    # @param events [Array<Event>]
    # @return [String] formatted summary text
    def format_summary_for_events(events)
      return "📊 *Summary*: 0 events" if events.empty?

      aggregator = Aggregator.new
      summary = aggregator.format_summary(events)
      format_summary(summary)
    end

    # Send a message with Markdown parse mode.
    #
    # @param text [String]
    # @return [TelegramResponse]
    def send_with_markdown(text)
      send_message(text, parse_mode: "MarkdownV2")
    end

    # Send a message with HTML parse mode.
    #
    # @param text [String]
    # @return [TelegramResponse]
    def send_with_html(text)
      send_message(text, parse_mode: "HTML")
    end

    # Check if the notifier is currently rate-limited.
    #
    # Checks both per-second and per-minute limits.
    #
    # @return [Boolean] true if rate limited, false otherwise
    def rate_limit_check
      @mutex.synchronize do
        return true if @recent_message_times.size >= MAX_MESSAGES_PER_MINUTE

        now = Time.now
        @recent_message_times.reject! { |t| (now - t) > 60 }
        @recent_message_times.size >= MAX_MESSAGES_PER_MINUTE
      end
    end

    # Send a message via the Telegram Bot API.
    #
    # @param text [String] the message text
    # @param parse_mode [String, nil]
    # @return [TelegramResponse]
    def send_telegram_api(text, parse_mode: nil)
      return TelegramResponse.new(success: false, error: "No bot token configured") unless config.telegram_bot_token && !config.telegram_bot_token.to_s.strip.empty?

      uri = URI("#{api_base}/sendMessage")

      params = {
        chat_id: config.notification_channel_id.to_s,
        text: text,
      }
      params[:parse_mode] = parse_mode if parse_mode

      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/x-www-form-urlencoded")
      request.body = URI.encode_www_form(params)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                  read_timeout: config.request_timeout || 30,
                                  open_timeout: config.request_timeout || 30) do |http|
        http.request(request)
      end

      body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      if response.is_a?(Net::HTTPSuccess)
        msg_id = body.dig("result", "message_id")
        TelegramResponse.new(success: true, message_id: msg_id)
      else
        error_msg = body["description"] || "Unknown Telegram API error"
        TelegramResponse.new(success: false, error: error_msg, api_error: body)
      end
    rescue JSON::ParserError
      TelegramResponse.new(success: false, error: "Failed to parse Telegram response")
    rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
      TelegramResponse.new(success: false, error: "Network error: #{e.message}")
    rescue StandardError => e
      TelegramResponse.new(success: false, error: "Unexpected error: #{e.class} - #{e.message}")
    end

    # Backward-compatible wrapper that calls send_events.
    #
    # @param events [Array<Event>]
    # @return [TelegramResponse, nil]
    def notify(events)
      return nil unless config.notifications_enabled?
      return TelegramResponse.new(success: false, error: "No events to send") if events.empty?

      send_events(events)
    end

    private

    # Truncate a message to Telegram's 4096 character limit.
    #
    # Tries to break at the last newline before the limit to avoid
    # cutting text in the middle of a line.
    #
    # @param text [String]
    # @return [String] truncated text
    def truncate_message(text)
      return text if text.length <= MAX_MESSAGE_LENGTH

      note = "\n\n⋯ *(truncated — #{text.length} chars)*"
      available = MAX_MESSAGE_LENGTH - note.length

      truncated = text[0...available]

      # Try to break at a newline
      break_at = truncated.rindex("\n")
      if break_at && break_at > available * 0.8
        truncated = truncated[0..break_at]
      end

      truncated + note
    end

    # Normalize a category string to a standard set.
    #
    # @param category [String, nil]
    # @return [String]
    def normalize_category(category)
      return "Other" unless category && !category.to_s.strip.empty?

      cat = category.to_s.strip.downcase
      case cat
      when /concert|live music|show|performance|gig|band|musician|music/
        "Music"
      when /comedy|stand-up|improv|joke|humor/
        "Comedy"
      when /festival|fair|carnival|cultural/
        "Festival"
      when /sport|game|match|tournament|athletic/
        "Sports"
      when /food|culinary|dining|restaurant|tasting|cook|food & drink/
        "Food & Drink"
      when /market|bazaar|craft|vendor/
        "Market"
      when /conference|workshop|seminar|lecture|class|training|education/
        "Education"
      when /theater|play|drama|musical|broadway/
        "Theater"
      when /family|kids|children|youth|teen/
        "Family"
      when /nightlife|club|bar|party|dance|dj|rave/
        "Nightlife"
      when /outdoor|park|trail|hiking|nature|camping/
        "Outdoor"
      when /religious|church|temple|mosque|spiritual/
        "Religious"
      when /politics|protest|rally|election|debate/
        "Politics"
      when /tech|startup|hackathon|developer|coding/
        "Technology"
      when /art|exhibition|gallery|museum|painting|sculpture/
        "Art"
      else
        "Other"
      end
    end

    # Check and enforce rate limits.
    #
    # @raise [StandardError] if rate limit would be exceeded
    def check_rate_limit!
      now = Time.now
      @recent_message_times.reject! { |t| (now - t) > 60 }

      if @recent_message_times.size >= MAX_MESSAGES_PER_MINUTE
        raise StandardError, "Rate limit exceeded: #{MAX_MESSAGES_PER_MINUTE} messages per minute"
      end

      if @last_send_at && (now - @last_send_at) < MIN_SEND_INTERVAL
        sleep(MIN_SEND_INTERVAL - (now - @last_send_at))
      end

      @last_send_at = Time.now
    end
  end
end
