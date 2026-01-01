# frozen_string_literal: true

module Indicators
  # Classifies market volatility based on ATR and determines appropriate
  # trading cycle interval for dynamic job scheduling
  #
  # Uses ATR as a percentage of price to classify into 4 levels:
  # - Very High (>= 3%): 3 minute interval (most frequent trading)
  # - High (>= 2%): 6 minute interval
  # - Medium (>= 1%): 12 minute interval
  # - Low (< 1%): 25 minute interval (least frequent trading)
  #
  # Higher volatility means more frequent trading cycles to capture
  # rapid market movements. Lower volatility allows longer intervals
  # to reduce costs and avoid overtrading in quiet markets.
  #
  # @example Basic usage
  #   result = Indicators::VolatilityClassifier.classify(5.0, 100.0)
  #   result.level    # => :very_high
  #   result.interval # => 3
  #
  # @example Classify for a specific symbol
  #   result = Indicators::VolatilityClassifier.classify_for_symbol("BTC")
  #   result.level    # => :high
  #   result.interval # => 6
  #
  class VolatilityClassifier
    # Volatility levels with corresponding intervals (in minutes)
    # Lower interval = more frequent trading cycles
    LEVELS = {
      very_high: 3,
      high: 6,
      medium: 12,
      low: 25
    }.freeze

    # Default ATR thresholds as percentage of price
    # These can be overridden via settings or custom thresholds parameter
    DEFAULT_THRESHOLDS = {
      very_high: 0.03, # 3% of price
      high: 0.02,      # 2% of price
      medium: 0.01     # 1% of price (below = low)
    }.freeze

    # Structured result containing volatility classification
    Result = Struct.new(:level, :interval, :atr_value, :atr_percentage, keyword_init: true)

    class << self
      # Classify volatility level based on ATR value and current price
      #
      # @param atr_value [Float, nil] ATR value from Calculator#atr
      # @param current_price [Float, nil] Current asset price
      # @param thresholds [Hash] Optional custom thresholds (keys: :very_high, :high, :medium)
      # @return [Result] Classification result with level, interval, atr values
      # @example
      #   result = classify(5.0, 100.0)
      #   result.level    # => :very_high
      #   result.interval # => 3
      def classify(atr_value, current_price, thresholds: DEFAULT_THRESHOLDS)
        return default_result if atr_value.nil? || current_price.nil? || current_price.zero?

        atr_percentage = atr_value / current_price
        level = determine_level(atr_percentage, thresholds)

        Result.new(
          level: level,
          interval: LEVELS[level],
          atr_value: atr_value,
          atr_percentage: atr_percentage
        )
      end

      # Classify volatility for a specific symbol by fetching market data
      #
      # Fetches 150 hourly candles from Binance, calculates ATR,
      # and classifies the result.
      #
      # @param symbol [String] Asset symbol (BTC, ETH, SOL, BNB)
      # @return [Result] Classification result
      # @example
      #   result = classify_for_symbol("BTC")
      #   result.level # => :high
      def classify_for_symbol(symbol)
        fetcher = DataIngestion::PriceFetcher.new
        candles = fetcher.fetch_klines(symbol, interval: "1h", limit: 150)
        current_price = candles.last[:close]

        calculator = Calculator.new
        atr_value = calculator.atr(candles, 14)

        classify(atr_value, current_price)
      rescue StandardError => e
        Rails.logger.warn "[VolatilityClassifier] Error for #{symbol}: #{e.message}"
        default_result
      end

      # Aggregate volatility across all configured assets
      #
      # Takes the highest volatility level among all assets
      # (most conservative approach - uses most frequent interval).
      # This ensures we don't miss trading opportunities during
      # volatile periods in any asset.
      #
      # @return [Result] Highest volatility classification among all assets
      # @example
      #   result = classify_all_assets
      #   result.level # => :very_high (if any asset is very volatile)
      def classify_all_assets
        results = Settings.assets.to_a.map { |symbol| classify_for_symbol(symbol) }

        # Return the highest volatility (smallest interval)
        results.min_by(&:interval)
      end

      private

      # Determine volatility level from ATR percentage
      #
      # @param atr_percentage [Float] ATR as a percentage of price
      # @param thresholds [Hash] Threshold values for each level
      # @return [Symbol] Volatility level (:very_high, :high, :medium, :low)
      def determine_level(atr_percentage, thresholds)
        if atr_percentage >= thresholds[:very_high]
          :very_high
        elsif atr_percentage >= thresholds[:high]
          :high
        elsif atr_percentage >= thresholds[:medium]
          :medium
        else
          :low
        end
      end

      # Default result when volatility cannot be determined
      #
      # Uses :medium level (12 min interval) as a safe default
      #
      # @return [Result] Default medium volatility result
      def default_result
        Result.new(
          level: :medium,
          interval: LEVELS[:medium],
          atr_value: nil,
          atr_percentage: nil
        )
      end
    end
  end
end
