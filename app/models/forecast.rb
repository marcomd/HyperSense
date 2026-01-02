# frozen_string_literal: true

# Stores price predictions from the Prophet forecasting module
#
# Each forecast record represents a prediction for a specific asset
# at a specific timeframe (1m, 15m, 1h). The actual price is filled
# in later when the prediction is validated.
#
class Forecast < ApplicationRecord
  VALID_TIMEFRAMES = %w[1m 15m 1h].freeze
  VALID_SYMBOLS = %w[BTC ETH SOL BNB].freeze

  # Direction threshold constants (percentage change)
  BEARISH_THRESHOLD_PCT = -0.5
  BULLISH_THRESHOLD_PCT = 0.5

  # Validations
  validates :symbol, presence: true, inclusion: { in: VALID_SYMBOLS }
  validates :timeframe, presence: true, inclusion: { in: VALID_TIMEFRAMES }
  validates :predicted_price, presence: true, numericality: { greater_than: 0 }
  validates :current_price, presence: true, numericality: { greater_than: 0 }
  validates :forecast_for, presence: true
  validates :actual_price, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :for_timeframe, ->(timeframe) { where(timeframe: timeframe) }
  scope :pending_validation, -> { where(actual_price: nil) }
  scope :validated, -> { where.not(actual_price: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :due_for_validation, -> { pending_validation.where("forecast_for <= ?", Time.current) }

  # Get the latest forecast for a symbol and timeframe
  # @param symbol [String] Asset symbol
  # @param timeframe [String] Timeframe (1m, 15m, 1h)
  # @return [Forecast, nil]
  def self.latest_for(symbol, timeframe)
    for_symbol(symbol).for_timeframe(timeframe).recent.first
  end

  # Get all latest forecasts for a symbol (all timeframes)
  # @param symbol [String] Asset symbol
  # @return [Hash] Forecasts by timeframe
  def self.latest_all_timeframes_for(symbol)
    VALID_TIMEFRAMES.to_h do |tf|
      forecast = latest_for(symbol, tf)
      [ tf, forecast&.to_context_hash ]
    end.compact
  end

  # Calculate prediction direction
  # @return [String] "bullish", "bearish", or "neutral"
  def direction
    return "neutral" if predicted_price == current_price

    pct_change = ((predicted_price - current_price) / current_price * 100).round(2)
    case pct_change
    when ..BEARISH_THRESHOLD_PCT then "bearish"
    when BULLISH_THRESHOLD_PCT.. then "bullish"
    else "neutral"
    end
  end

  # Check if this forecast has been validated
  # @return [Boolean]
  def validated?
    actual_price.present?
  end

  # Validate the forecast against the actual price
  # @param actual [BigDecimal, Float] The actual price at forecast_for time
  # @return [Boolean] Whether the update succeeded
  def validate_with_actual!(actual)
    calculated_mae = (predicted_price - actual).abs
    calculated_mape = ((predicted_price - actual).abs / actual * 100) if actual.positive?

    update!(
      actual_price: actual,
      mae: calculated_mae,
      mape: calculated_mape
    )
  end

  # Convert to hash for context assembly
  # @return [Hash]
  def to_context_hash
    {
      current_price: current_price.to_f,
      predicted_price: predicted_price.to_f,
      direction: direction,
      forecast_for: forecast_for.iso8601,
      created_at: created_at.iso8601
    }
  end

  # Calculate percentage change from current to predicted
  # @return [Float]
  def predicted_change_pct
    return 0.0 if current_price.zero?

    ((predicted_price - current_price) / current_price * 100).round(2)
  end
end
