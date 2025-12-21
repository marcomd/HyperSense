# frozen_string_literal: true

module DataIngestion
  # Fetches market sentiment data from various sources
  #
  # Sources:
  # - Fear & Greed Index (alternative.me)
  #
  class SentimentFetcher
    FEAR_GREED_URL = "https://api.alternative.me/fng/"

    def initialize
      @conn = Faraday.new do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
      end
    end

    # Fetch all sentiment indicators
    #
    # @return [Hash] Combined sentiment data
    #
    def fetch_all
      {
        fear_greed: fetch_fear_greed,
        fetched_at: Time.current
      }
    rescue StandardError => e
      Rails.logger.error "[SentimentFetcher] Error: #{e.message}"
      { error: e.message, fetched_at: Time.current }
    end

    # Fetch Fear & Greed Index
    #
    # Values:
    # - 0-24: Extreme Fear
    # - 25-49: Fear
    # - 50-74: Greed
    # - 75-100: Extreme Greed
    #
    # @param limit [Integer] Number of historical values (default: 1)
    # @return [Hash] Fear & Greed data
    #
    def fetch_fear_greed(limit: 1)
      response = @conn.get(FEAR_GREED_URL, { limit: limit })

      raise "API Error: #{response.status}" unless response.success?

      data = response.body["data"]&.first
      return { error: "No data available" } unless data

      {
        value: data["value"].to_i,
        classification: data["value_classification"],
        timestamp: Time.at(data["timestamp"].to_i),
        time_until_update: data["time_until_update"]
      }
    end

    # Get sentiment interpretation for trading
    #
    # @param fear_greed_value [Integer] Fear & Greed value (0-100)
    # @return [Hash] Interpretation with trading bias
    #
    def interpret_sentiment(fear_greed_value)
      case fear_greed_value
      when 0..10
        { level: :extreme_fear, bias: :contrarian_bullish, strength: 1.0 }
      when 11..24
        { level: :extreme_fear, bias: :contrarian_bullish, strength: 0.7 }
      when 25..39
        { level: :fear, bias: :slightly_bullish, strength: 0.3 }
      when 40..60
        { level: :neutral, bias: :neutral, strength: 0.0 }
      when 61..74
        { level: :greed, bias: :slightly_bearish, strength: 0.3 }
      when 75..89
        { level: :extreme_greed, bias: :contrarian_bearish, strength: 0.7 }
      when 90..100
        { level: :extreme_greed, bias: :contrarian_bearish, strength: 1.0 }
      else
        { level: :unknown, bias: :neutral, strength: 0.0 }
      end
    end
  end
end
