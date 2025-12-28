# frozen_string_literal: true

# Stores point-in-time market data for each tracked asset
#
# Each snapshot captures price, volume, technical indicators, and sentiment
# at a specific moment. Created every minute by MarketSnapshotJob.
#
# Used for:
# - Providing context to the reasoning engine
# - Historical analysis and backtesting
# - Dashboard visualization
# - Technical indicator calculation (EMA, RSI, MACD, Pivots)
#
# @example Get latest snapshot for BTC
#   snapshot = MarketSnapshot.latest_for("BTC")
#   snapshot.price        # => 97000.0
#   snapshot.rsi_signal   # => :neutral
#
class MarketSnapshot < ApplicationRecord
  # RSI threshold constants for overbought/oversold signals
  RSI_OVERSOLD_THRESHOLD = 30
  RSI_OVERBOUGHT_THRESHOLD = 70

  # Validations
  validates :symbol, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :captured_at, presence: true
  validates :symbol, uniqueness: { scope: :captured_at }

  # Scopes
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :recent, -> { order(captured_at: :desc) }
  scope :since, ->(time) { where("captured_at >= ?", time) }
  scope :last_hours, ->(hours) { since(hours.hours.ago) }
  scope :last_days, ->(days) { since(days.days.ago) }

  # Get the latest snapshot for each symbol
  scope :latest_per_symbol, -> {
    select("DISTINCT ON (symbol) *")
      .order(:symbol, captured_at: :desc)
  }

  # Class methods
  class << self
    # Get latest snapshot for a specific symbol
    def latest_for(symbol)
      for_symbol(symbol).recent.first
    end

    # Get price history for indicator calculation
    def prices_for(symbol, limit: 150)
      for_symbol(symbol)
        .recent
        .limit(limit)
        .pluck(:price)
        .reverse
    end
  end

  # Instance methods

  # Get a specific indicator value from the JSONB indicators column
  #
  # @param name [String, Symbol] Indicator name (e.g., "rsi_14", "ema_50")
  # @return [Numeric, Hash, nil] Indicator value or nil if not present
  # @example
  #   snapshot.indicator("rsi_14")  # => 62.5
  #   snapshot.indicator("macd")    # => { "macd" => 2.5, "signal" => 1.8, "histogram" => 0.7 }
  def indicator(name)
    indicators&.dig(name.to_s)
  end

  # Check if current price is above a specific EMA
  #
  # @param period [Integer] EMA period (20, 50, or 100)
  # @return [Boolean, nil] true if price > EMA, false if below, nil if EMA unavailable
  # @example
  #   snapshot.above_ema?(50)  # => true
  def above_ema?(period)
    ema_value = indicator("ema_#{period}")
    return nil unless ema_value

    price > ema_value
  end

  # Get RSI classification based on standard overbought/oversold levels
  #
  # @return [Symbol, nil] :oversold (RSI < 30), :overbought (RSI > 70), :neutral, or nil
  # @example
  #   snapshot.rsi_signal  # => :neutral
  def rsi_signal
    rsi = indicator("rsi_14")
    return nil unless rsi

    case rsi
    when 0..RSI_OVERSOLD_THRESHOLD then :oversold
    when RSI_OVERBOUGHT_THRESHOLD..100 then :overbought
    else :neutral
    end
  end

  # Get MACD signal based on histogram direction
  #
  # @return [Symbol, nil] :bullish (positive histogram), :bearish (negative), or nil
  # @example
  #   snapshot.macd_signal  # => :bullish
  def macd_signal
    macd_data = indicator("macd")
    return nil unless macd_data

    histogram = macd_data["histogram"]
    return nil unless histogram

    histogram.positive? ? :bullish : :bearish
  end
end
