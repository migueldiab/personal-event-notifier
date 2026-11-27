# frozen_string_literal: true

require "date"
require "stringio"
require "pdf/reader"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Fallback scraper for the ACL Live TCPDF calendar at /events-tickets/pdf.
    #
    # The PDF is a positioned-text monthly grid: TCPDF emits no semantic tables,
    # no venue, no URLs and no year. This scraper reconstructs the day columns
    # from character offsets in pdf-reader's layout-mode text, groups wrapped
    # title lines until a standalone time line, and emits the same Event objects
    # (and therefore the same JSON schema) as the HTML scraper.
    #
    # Venue is defaulted because the PDF does not carry per-event venues; use
    # the `venue:` config option when the calendar belongs to a single stage.
    class AclLivePdfScraper < BaseScraper
      BASE_URL = "https://www.acllive.com".freeze
      PDF_PATH = "/events-tickets/pdf".freeze
      VENUE_NAME = "ACL Live at The Moody Theater".freeze
      SOURCE = "acl_live".freeze
      WEEKDAYS = %w[SUNDAY MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY].freeze
      TIME_ONLY = /\A(\d{1,2}:\d{2}\s*(?:am|pm))\z/i.freeze
      FOOTER = /Powered by TCPDF/i.freeze

      attr_reader :venue_name

      # @param config [Config, Hash, nil] scraper configuration; :venue overrides
      #   the default venue name
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config.dup : {}
        @venue_name = cfg.delete(:venue) || VENUE_NAME
        cfg[:name] = "acl_live_pdf"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        cfg[:rate_limit_delay] = 3.0
        cfg[:date_range_days] = 30
        super(cfg)
      end

      # Fetch the PDF and extract a full month of events.
      #
      # @return [Array<Event>]
      def events
        result = parse(fetch_pdf)
        log_info "PDF calendar: extracted #{result.size} events"
        result
      end

      # BaseScraper contract alias.
      #
      # @param source [String, IO] PDF bytes, a file path, or an IO
      # @return [Array<Event>]
      def parse_response(source, **options)
        parse(source, **options) # rubocop:disable Style/ArgumentsForwarding
      end

      # Parse PDF bytes (or a path/IO) into Event objects.
      #
      # @param source [String, IO] PDF bytes, path, or IO
      # @param year [Integer, nil] override the year taken from PDF metadata
      # @param month [Integer, nil] override the month taken from the grid header
      # @return [Array<Event>]
      def parse(source, year: nil, month: nil)
        bytes = pdf_bytes_from(source)
        return [] if bytes.nil? || bytes.empty?

        reader = PDF::Reader.new(StringIO.new(bytes))
        pages = reader.pages.map(&:text)
        resolved_year = year || year_from_metadata(reader)

        parse_pages(pages, year: resolved_year, month: month || month_from_pages(pages))
      rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError,
             ArgumentError, IOError
        []
      end

      # Parse pre-extracted layout text. Exposed for fixtures and cross-checks.
      #
      # @param text [String] layout-mode text of the calendar
      # @param year [Integer] calendar year
      # @param month [Integer, nil] month number; detected from the header if nil
      # @return [Array<Event>]
      def parse_layout(text, year:, month: nil)
        resolved_month = month || month_from_pages([text.to_s])
        return [] unless resolved_month

        parse_pages([text.to_s], year: year, month: resolved_month)
      end

      private

      def parse_pages(pages, year:, month:)
        return [] unless year && month

        @extracted_events = []
        @columns = []
        @positions = []
        @calendar_year = year
        @calendar_month = month

        pages.each do |page_text|
          page_text.to_s.each_line { |raw_line| consume_line(raw_line.chomp) }
        end
        flush_columns!
        @extracted_events
      end

      def consume_line(line)
        stripped = line.strip
        return if stripped.empty? || FOOTER.match?(stripped)
        return if header_line?(stripped)

        day_numbers = day_row(line)
        if day_numbers
          flush_columns!
          @positions = day_numbers.map(&:first)
          @columns = day_numbers.map { |(_, day)| { day: day, lines: [] } }
        elsif @columns.any?
          word_groups(line).each do |group|
            index = @positions.rindex { |position| position <= group[:start] } || 0
            @columns[index][:lines] << group[:text]
          end
        end
      end

      # A day row is a run of small integers, e.g. "1    2    3" or "29   30".
      # Returns [character_offset, day_number] pairs.
      def day_row(line)
        stripped = line.strip
        return nil unless stripped.match?(/\A\d{1,2}(?:\s+\d{1,2})*\z/)

        numbers = []
        line.scan(/\d{1,2}/) do
          numbers << [Regexp.last_match.begin(0), Regexp.last_match[0].to_i]
        end
        numbers
      end

      # Group words into cells: a single space stays inside a title, while the
      # wide gaps TCPDF puts between columns start a new cell. Avoids the
      # off-by-one errors of slicing at fixed character boundaries.
      def word_groups(line)
        groups = []
        line.scan(/\S+/) do
          word = Regexp.last_match[0]
          start_at = Regexp.last_match.begin(0)
          current = groups.last
          if current && (start_at - current[:end] <= 1)
            current[:text] << " " << word
            current[:end] = start_at + word.length
          else
            groups << { text: +word, start: start_at, end: start_at + word.length }
          end
        end
        groups
      end

      def flush_columns!
        @columns.each do |column|
          build_events(column[:lines], column[:day]).each { |event| @extracted_events << event }
          column[:lines].clear
        end
      end

      def build_events(lines, day)
        return [] unless Date.valid_date?(@calendar_year, @calendar_month, day)

        date = Date.new(@calendar_year, @calendar_month, day)
        events = []
        title_lines = []

        lines.each do |raw|
          text = raw.to_s.strip
          next if text.empty?

          if (match = text.match(TIME_ONLY))
            title = join_title(title_lines)
            events << build_event(title, date, match[1]) unless title.empty?
            title_lines = []
          else
            title_lines << text
          end
        end

        trailing = join_title(title_lines)
        events << build_event(trailing, date, nil) unless trailing.empty?
        events
      end

      def join_title(lines)
        lines.join(" ").gsub(/\s+/, " ").strip
      end

      def build_event(title, date, time)
        Event.from_hash(
          title: title,
          date: date,
          time: time && normalize_time(time),
          venue: Venue.from_hash(name: venue_name),
          url: nil,
          source: SOURCE
        )
      end

      def header_line?(stripped)
        month_names = Date::MONTHNAMES.compact + Date::ABBR_MONTHNAMES.compact
        return true if month_names.any? { |name| name.casecmp?(stripped) }

        words = stripped.split(/\s+/)
        words.any? && words.all? { |word| WEEKDAYS.include?(word.upcase) }
      end

      def month_from_pages(pages)
        month_names = Date::MONTHNAMES.compact + Date::ABBR_MONTHNAMES.compact
        pages.each do |text|
          text.to_s.each_line do |line|
            word = line.strip
            next unless word.match?(/\A[A-Za-z]{3,}\z/)

            found = month_names.find { |name| name.casecmp?(word) }
            return Date::MONTHNAMES.index(found) if found
          end
        end
        nil
      end

      # TCPDF writes the generation date into XMP metadata; the visible grid
      # only names the month. Prefer that year over the wall clock.
      def year_from_metadata(reader)
        metadata = reader.metadata.to_s
        match = metadata.match(/<xmp:CreateDate>(\d{4})-(\d{2})-(\d{2})/)
        return match[1].to_i if match

        info = reader.info || {}
        creation = info[:CreationDate] || info["CreationDate"]
        match = creation.to_s.match(/D:(\d{4})/) if creation
        return match[1].to_i if match

        match = metadata.match(/\b(\d{4})-\d{2}-\d{2}\b/)
        match ? match[1].to_i : Date.today.year
      end

      def pdf_bytes_from(source)
        return source.read.to_s.b if source.respond_to?(:read)
        return nil unless source.is_a?(String)
        return source.b if source.start_with?("%PDF")
        return File.binread(source).b if File.file?(source)

        nil
      end

      def fetch_pdf
        url = build_url(PDF_PATH)
        response = http_get(url, "Accept" => "application/pdf")
        raise ScraperError, "HTTP #{response.code}: #{url}" unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s.b
      end
    end
  end
end
