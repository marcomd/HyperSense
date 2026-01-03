# frozen_string_literal: true

module Indicators
  # Technical indicator calculator for trading analysis
  #
  # Implements common trading indicators:
  # - EMA (Exponential Moving Average)
  # - RSI (Relative Strength Index)
  # - MACD (Moving Average Convergence Divergence)
  # - ATR (Average True Range) for volatility measurement
  # - Pivot Points (Support/Resistance levels)
  #
  # @example Basic usage
  #   calculator = Indicators::Calculator.new
  #   prices = [100, 102, 101, 103, 105, 104, 106]
  #   calculator.rsi(prices) # => 62.5
  #
  class Calculator
    # Calculate EMA (Exponential Moving Average) for a series of prices
    #
    # Uses the standard EMA formula: EMA = Price * k + EMA(prev) * (1 - k)
    # where k = 2 / (period + 1)
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param period [Integer] EMA period (e.g., 20, 50, 100)
    # @return [Float, nil] Current EMA value, or nil if insufficient data
    # @example
    #   calculator.ema([100, 102, 101, 103, 105], 3)
    #   # => 103.5
    def ema(prices, period)
      return nil if prices.size < period

      k = 2.0 / (period + 1)

      # Initialize with SMA
      initial_sma = prices.first(period).sum.to_f / period

      # Calculate EMA
      prices.drop(period).reduce(initial_sma) do |prev_ema, price|
        (price * k) + (prev_ema * (1 - k))
      end
    end

    # Calculate RSI (Relative Strength Index)
    #
    # RSI measures momentum on a scale of 0-100:
    # - Below 30: Oversold (potential buy signal)
    # - Above 70: Overbought (potential sell signal)
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param period [Integer] RSI period (default: 14)
    # @return [Float, nil] RSI value (0-100), or nil if insufficient data
    # @example
    #   calculator.rsi([100, 102, 101, 103, 105, 104, 106, 108, 107, 109, 111, 110, 112, 114, 113])
    #   # => 66.67
    def rsi(prices, period = 14)
      return nil if prices.size < period + 1

      changes = prices.each_cons(2).map { |a, b| b - a }

      gains = changes.map { |c| c.positive? ? c : 0 }
      losses = changes.map { |c| c.negative? ? c.abs : 0 }

      avg_gain = gains.last(period).sum.to_f / period
      avg_loss = losses.last(period).sum.to_f / period

      return 100.0 if avg_loss.zero?

      rs = avg_gain / avg_loss
      100.0 - (100.0 / (1.0 + rs))
    end

    # Calculate MACD (Moving Average Convergence Divergence)
    #
    # MACD is a trend-following momentum indicator:
    # - Positive histogram: Bullish momentum
    # - Negative histogram: Bearish momentum
    # - Crossovers signal potential trend changes
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param fast_period [Integer] Fast EMA period (default: 12)
    # @param slow_period [Integer] Slow EMA period (default: 26)
    # @param signal_period [Integer] Signal line period (default: 9)
    # @return [Hash, nil] MACD components or nil if insufficient data
    # @example
    #   calculator.macd(prices)
    #   # => { macd: 2.5, signal: 1.8, histogram: 0.7 }
    def macd(prices, fast_period: 12, slow_period: 26, signal_period: 9)
      return nil if prices.size < slow_period

      # Calculate MACD line (fast EMA - slow EMA)
      macd_values = []
      (slow_period..prices.size).each do |i|
        subset = prices.first(i)
        fast = ema(subset, fast_period)
        slow = ema(subset, slow_period)
        macd_values << (fast - slow) if fast && slow
      end

      return nil if macd_values.size < signal_period

      # Calculate signal line (EMA of MACD)
      signal_line = ema(macd_values, signal_period)
      current_macd = macd_values.last

      {
        macd: current_macd,
        signal: signal_line,
        histogram: current_macd - signal_line
      }
    end

    # Calculate ATR (Average True Range) for volatility measurement
    #
    # ATR measures market volatility using true range:
    # - True Range = max(high - low, |high - prev_close|, |low - prev_close|)
    # - ATR = EMA of True Range values over the specified period
    #
    # Higher ATR indicates more volatile markets, useful for:
    # - Setting stop-loss distances
    # - Determining position sizing
    # - Adjusting trading frequency based on market conditions
    #
    # @param candles [Array<Hash>] OHLCV candle data with :high, :low, :close keys
    # @param period [Integer] ATR period (default: 14)
    # @return [Float, nil] Current ATR value, or nil if insufficient data
    # @example
    #   candles = [{ high: 110, low: 100, close: 105 }, ...]
    #   calculator.atr(candles, 14)
    #   # => 8.5
    def atr(candles, period = 14)
      return nil if candles.size < period + 1

      # Calculate True Range for each candle (starting from index 1)
      # True Range accounts for gaps between candles
      true_ranges = candles.each_cons(2).map do |prev, curr|
        high_low = curr[:high] - curr[:low]
        high_close = (curr[:high] - prev[:close]).abs
        low_close = (curr[:low] - prev[:close]).abs
        [ high_low, high_close, low_close ].max
      end

      # Use EMA to smooth the true ranges
      ema(true_ranges, period)
    end

    # Calculate Pivot Points (Floor Trader Pivots)
    #
    # Pivot points are key support/resistance levels used by traders:
    # - PP: Central pivot point
    # - R1, R2: Resistance levels above the pivot
    # - S1, S2: Support levels below the pivot
    #
    # @param high [Numeric] Previous period high
    # @param low [Numeric] Previous period low
    # @param close [Numeric] Previous period close
    # @return [Hash] Pivot point levels with keys :pp, :r1, :r2, :s1, :s2
    # @example
    #   calculator.pivot_points(105, 95, 100)
    #   # => { pp: 100.0, r1: 105.0, r2: 110.0, s1: 95.0, s2: 90.0 }
    def pivot_points(high, low, close)
      pp = (high + low + close) / 3.0

      {
        pp: pp,
        r1: (2 * pp) - low,
        r2: pp + (high - low),
        s1: (2 * pp) - high,
        s2: pp - (high - low)
      }
    end

    # Calculate all indicators for an asset in a single call
    #
    # Convenience method that computes EMA (20, 50, 100, 200), RSI (14),
    # MACD, pivot points, and optionally ATR.
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param high [Numeric, nil] Period high (for pivot points)
    # @param low [Numeric, nil] Period low (for pivot points)
    # @param candles [Array<Hash>, nil] OHLCV candle data (for ATR calculation)
    # @return [Hash] All calculated indicators with keys :ema_20, :ema_50, :ema_100, :ema_200, :rsi_14, :macd, :pivot_points, :atr_14
    # @example
    #   calculator.calculate_all(prices, high: 105, low: 95, candles: candles)
    #   # => { ema_20: 102.5, ema_50: 100.0, ema_100: 98.5, ema_200: 97.0, rsi_14: 55.0, macd: {...}, pivot_points: {...}, atr_14: 5.2 }
    def calculate_all(prices, high: nil, low: nil, candles: nil)
      {
        ema_20: ema(prices, 20),
        ema_50: ema(prices, 50),
        ema_100: ema(prices, 100),
        ema_200: ema(prices, 200),
        rsi_14: rsi(prices, 14),
        macd: macd(prices),
        pivot_points: high && low ? pivot_points(high, low, prices.last) : nil,
        atr_14: candles ? atr(candles, 14) : nil
      }
    end
  end
end
