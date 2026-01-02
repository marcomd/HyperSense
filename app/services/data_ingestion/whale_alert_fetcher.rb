# frozen_string_literal: true

module DataIngestion
  # Fetches whale alerts from whale-alert.io free endpoint
  #
  # Monitors large capital movements (transfers, mints, burns)
  # that may indicate smart money positioning.
  #
  # @example Fetch recent whale alerts
  #   fetcher = DataIngestion::WhaleAlertFetcher.new
  #   alerts = fetcher.fetch
  #   # => [{ action: "transferred", amount: "1,580 BTC", usd_value: "$138M", severity: 6 }, ...]
  #
  class WhaleAlertFetcher
    ENDPOINT = "https://whale-alert.io/data.json"
    CACHE_DURATION = 2.minutes
    MAX_ALERTS = 10

    # Emoji patterns for categorizing alerts
    EMOJI_PATTERNS = {
      transfer: "🚨",
      minted: "💵",
      burned: "🔥"
    }.freeze

    def initialize
      @logger = Rails.logger
      @cache_key = "whale_alert_fetcher:data"
    end

    # Fetch and parse whale alerts
    # @return [Array<Hash>] Array of parsed alerts
    def fetch
      cached = Rails.cache.read(@cache_key)
      return cached if cached

      data = fetch_from_endpoint
      alerts = parse_alerts(data["alerts"] || [])

      Rails.cache.write(@cache_key, alerts, expires_in: CACHE_DURATION)
      alerts
    rescue StandardError => e
      @logger.error "[WhaleAlertFetcher] Error fetching alerts: #{e.message}"
      []
    end

    # Get recent alerts for context assembly
    # @param limit [Integer] Maximum number of alerts
    # @return [Array<Hash>] Recent alerts
    def recent_alerts(limit: 5)
      fetch.first(limit)
    end

    # Get alerts filtered by asset symbol
    # @param symbol [String] Asset symbol (BTC, ETH, etc.)
    # @return [Array<Hash>] Filtered alerts
    def alerts_for_symbol(symbol)
      keyword = symbol.upcase
      fetch.select { |alert| alert[:amount]&.include?(keyword) }
    end

    private

    def fetch_from_endpoint
      # Build URL with parameters for BTC monitoring
      url = "#{ENDPOINT}?alerts=#{MAX_ALERTS}&prices=BTC&hodl=bitcoin%2CBTC&potential_profit=bitcoin%2CBTC"

      response = Faraday.get(url) do |req|
        req.options.timeout = 10
        req.options.open_timeout = 5
        req.headers["User-Agent"] = "HyperSense Trading Agent"
      end

      raise "HTTP #{response.status}" unless response.success?

      JSON.parse(response.body)
    end

    def parse_alerts(alerts_array)
      alerts_array.filter_map do |alert_str|
        parse_single_alert(alert_str)
      end
    end

    def parse_single_alert(alert_str)
      # Alert format: "timestamp,emojis,amount,usd_value,action,link"
      # Example: "1766606943,🚨🚨🚨🚨🚨🚨,\"1,580 #BTC\",\"138,397,727 USD\",\" transferred...\",https://..."
      parts = alert_str.split(",")
      return nil if parts.size < 5

      timestamp = parse_timestamp(parts[0])
      emojis = parts[1]
      amount = clean_amount(parts[2])
      usd_value = clean_usd(parts[3])
      action = clean_action(parts[4])
      link = parts[5]&.strip

      {
        timestamp: timestamp,
        severity: calculate_severity(emojis),
        alert_type: detect_alert_type(emojis),
        amount: amount,
        usd_value: usd_value,
        action: action,
        link: link,
        signal: interpret_signal(emojis, action)
      }
    rescue StandardError => e
      @logger.warn "[WhaleAlertFetcher] Failed to parse alert: #{e.message}"
      nil
    end

    def parse_timestamp(ts_str)
      timestamp = ts_str.to_i
      return nil if timestamp.zero?

      Time.at(timestamp)
    end

    def clean_amount(amount_str)
      # Remove quotes and clean up: "\"1,580 #BTC\"" -> "1,580 BTC"
      amount_str&.gsub(/["#]/, "")&.strip
    end

    def clean_usd(usd_str)
      # Remove quotes: "\"138,397,727 USD\"" -> "$138M"
      value = usd_str&.gsub(/["\s]/, "")&.gsub("USD", "")&.strip
      return nil if value.blank?

      format_usd(value.tr(",", "").to_f)
    end

    def clean_action(action_str)
      # Remove leading space and quotes
      action_str&.gsub('"', "")&.strip&.downcase
    end

    def calculate_severity(emojis)
      # Count emojis to determine severity (more = more significant)
      emojis&.scan(/[🚨💵🔥]/)&.size || 0
    end

    def detect_alert_type(emojis)
      return :transfer if emojis&.include?("🚨")
      return :minted if emojis&.include?("💵")
      return :burned if emojis&.include?("🔥")

      :unknown
    end

    def interpret_signal(emojis, action)
      # Interpret what the whale movement might mean for the market
      action_lower = action&.downcase || ""

      if emojis&.include?("💵")
        # Stablecoin minted - potential buying power entering
        :potentially_bullish
      elsif emojis&.include?("🔥")
        # Stablecoin burned - reducing supply
        :neutral
      elsif action_lower.include?("binance") || action_lower.include?("exchange")
        # Transfer to exchange - potential selling pressure
        action_lower.include?("from") ? :potentially_bullish : :potentially_bearish
      else
        # General transfer - neutral signal
        :neutral
      end
    end

    def format_usd(value)
      return nil if value.nil? || value.zero?

      if value >= 1_000_000_000
        "$#{(value / 1_000_000_000).round(1)}B"
      elsif value >= 1_000_000
        "$#{(value / 1_000_000).round(1)}M"
      elsif value >= 1_000
        "$#{(value / 1_000).round(1)}K"
      else
        "$#{value.round(2)}"
      end
    end
  end
end
