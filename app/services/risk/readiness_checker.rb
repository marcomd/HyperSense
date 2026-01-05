# frozen_string_literal: true

module Risk
  # Validates that all required data is available before trading
  #
  # Checks:
  # - Valid MacroStrategy (not fallback from parse error)
  # - Forecasts exist for at least one asset
  # - Fresh market data (< 5 min old)
  # - Sentiment data available
  #
  # This ensures the trading agent has all critical context before making
  # decisions with real money. Trading is blocked if any required data
  # is missing or stale.
  #
  # @example
  #   checker = Risk::ReadinessChecker.new
  #   result = checker.check
  #
  #   unless result.ready?
  #     Rails.logger.warn "Data not ready: #{result.reason}"
  #     return []
  #   end
  #
  class ReadinessChecker
    # Result struct for readiness check
    #
    # @attr ready [Boolean] Whether all required data is present
    # @attr missing [Array<String>] List of missing data items
    ReadinessResult = Struct.new(:ready, :missing, keyword_init: true) do
      # @return [Boolean] Whether system is ready for trading
      def ready?
        ready
      end

      # @return [String] Human-readable reason for not being ready
      def reason
        missing.join(", ")
      end
    end

    # Default configuration values
    DEFAULT_MARKET_DATA_MAX_AGE_MINUTES = 5
    DEFAULT_FORECAST_MAX_AGE_HOURS = 1
    DEFAULT_SENTIMENT_MAX_AGE_HOURS = 24

    def initialize
      @logger = Rails.logger
    end

    # Check if all required data is available for trading
    #
    # @return [ReadinessResult] Result with ready status and missing items
    def check
      missing = []

      missing << "valid_macro_strategy" unless valid_macro_strategy?
      missing << "forecasts" unless forecasts_available?
      missing << "fresh_market_data" unless fresh_market_data?
      missing << "sentiment_data" unless sentiment_available?

      ReadinessResult.new(ready: missing.empty?, missing: missing)
    end

    # Current state summary
    #
    # @return [Hash] Detailed status of each check
    def status
      {
        valid_macro_strategy: valid_macro_strategy?,
        forecasts_available: forecasts_available?,
        fresh_market_data: fresh_market_data?,
        sentiment_available: sentiment_available?,
        ready: check.ready?
      }
    end

    private

    # Check if a valid macro strategy exists (not a fallback from parse error)
    #
    # @return [Boolean] True if valid strategy exists
    def valid_macro_strategy?
      return false unless readiness_enabled?(:require_macro_strategy)

      strategy = MacroStrategy.active
      return false unless strategy

      # Reject fallback neutral strategies created from parse errors
      !strategy.market_narrative.include?("Unable to parse")
    end

    # Check if forecasts exist for at least one configured asset
    #
    # @return [Boolean] True if forecasts are available
    def forecasts_available?
      return false unless readiness_enabled?(:require_forecasts)

      max_age = forecast_max_age_hours.hours.ago

      Settings.assets.to_a.any? do |symbol|
        Forecast.for_symbol(symbol).where("created_at > ?", max_age).exists?
      end
    end

    # Check if market data (snapshots) are fresh for all assets
    #
    # @return [Boolean] True if all assets have recent market data
    def fresh_market_data?
      return false unless readiness_enabled?(:require_fresh_market_data)

      max_age = market_data_max_age_minutes.minutes.ago

      Settings.assets.to_a.all? do |symbol|
        snapshot = MarketSnapshot.latest_for(symbol)
        snapshot && snapshot.created_at > max_age
      end
    end

    # Check if sentiment data (Fear & Greed) is available
    #
    # @return [Boolean] True if sentiment data exists
    def sentiment_available?
      return false unless readiness_enabled?(:require_sentiment)

      latest = MarketSnapshot.order(created_at: :desc).first
      return false unless latest&.sentiment

      # Sentiment is stored as { "fear_greed" => { "value" => ..., "classification" => ... } }
      latest.sentiment.dig("fear_greed", "value").present?
    end

    # Check if a specific readiness requirement is enabled
    #
    # @param key [Symbol] The readiness requirement key
    # @return [Boolean] True if requirement is enabled (defaults to true)
    def readiness_enabled?(key)
      return true unless Settings.respond_to?(:readiness)
      return true unless Settings.readiness.respond_to?(key)

      Settings.readiness.send(key) != false
    end

    # Configuration helpers

    def market_data_max_age_minutes
      if Settings.respond_to?(:readiness) && Settings.readiness.respond_to?(:market_data_max_age_minutes)
        Settings.readiness.market_data_max_age_minutes
      else
        DEFAULT_MARKET_DATA_MAX_AGE_MINUTES
      end
    end

    def forecast_max_age_hours
      if Settings.respond_to?(:readiness) && Settings.readiness.respond_to?(:forecast_max_age_hours)
        Settings.readiness.forecast_max_age_hours
      else
        DEFAULT_FORECAST_MAX_AGE_HOURS
      end
    end

    def sentiment_max_age_hours
      if Settings.respond_to?(:readiness) && Settings.readiness.respond_to?(:sentiment_max_age_hours)
        Settings.readiness.sentiment_max_age_hours
      else
        DEFAULT_SENTIMENT_MAX_AGE_HOURS
      end
    end
  end
end
