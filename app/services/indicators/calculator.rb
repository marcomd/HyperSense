# frozen_string_literal: true

module Indicators
  # Technical indicator calculator
  #
  # Implements common trading indicators:
  # - EMA (Exponential Moving Average)
  # - RSI (Relative Strength Index)
  # - MACD (Moving Average Convergence Divergence)
  # - Pivot Points (Support/Resistance levels)
  #
  class Calculator
    # Calculate EMA for a series of prices
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param period [Integer] EMA period (e.g., 20, 50, 100)
    # @return [Float] Current EMA value
    #
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
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param period [Integer] RSI period (default: 14)
    # @return [Float] RSI value (0-100)
    #
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

    # Calculate MACD
    #
    # @param prices [Array<Numeric>] Price history (oldest first)
    # @param fast_period [Integer] Fast EMA period (default: 12)
    # @param slow_period [Integer] Slow EMA period (default: 26)
    # @param signal_period [Integer] Signal line period (default: 9)
    # @return [Hash] { macd:, signal:, histogram: }
    #
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

    # Calculate Pivot Points (Floor Trader Pivots)
    #
    # @param high [Numeric] Previous period high
    # @param low [Numeric] Previous period low
    # @param close [Numeric] Previous period close
    # @return [Hash] { pp:, r1:, r2:, s1:, s2: }
    #
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

    # Calculate all indicators for an asset
    #
    # @param prices [Array<Numeric>] Price history
    # @param high [Numeric] Period high (for pivot points)
    # @param low [Numeric] Period low (for pivot points)
    # @return [Hash] All calculated indicators
    #
    def calculate_all(prices, high: nil, low: nil)
      {
        ema_20: ema(prices, 20),
        ema_50: ema(prices, 50),
        ema_100: ema(prices, 100),
        rsi_14: rsi(prices, 14),
        macd: macd(prices),
        pivot_points: high && low ? pivot_points(high, low, prices.last) : nil
      }
    end
  end
end
