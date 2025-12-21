# frozen_string_literal: true

# Stores point-in-time market data for each tracked asset
#
# Used for:
# - Providing context to the reasoning engine
# - Historical analysis and backtesting
# - Dashboard visualization
#
class MarketSnapshot < ApplicationRecord
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

  # Get a specific indicator value
  def indicator(name)
    indicators&.dig(name.to_s)
  end

  # Check if price is above EMA
  def above_ema?(period)
    ema_value = indicator("ema_#{period}")
    return nil unless ema_value

    price > ema_value
  end

  # Get RSI classification
  def rsi_signal
    rsi = indicator("rsi_14")
    return nil unless rsi

    case rsi
    when 0..30 then :oversold
    when 70..100 then :overbought
    else :neutral
    end
  end

  # Get MACD signal
  def macd_signal
    macd_data = indicator("macd")
    return nil unless macd_data

    histogram = macd_data["histogram"]
    return nil unless histogram

    histogram.positive? ? :bullish : :bearish
  end
end
