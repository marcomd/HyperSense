# frozen_string_literal: true

# Periodic job to generate price forecasts using Prophet
#
# Runs every 5 minutes to:
# 1. Generate new forecasts for all configured assets
# 2. Validate past forecasts against actual prices
#
# Uses MarketSnapshot historical data to train Prophet models
# and predict prices at 1m, 15m, and 1h intervals.
#
class ForecastJob < ApplicationJob
  queue_as :analysis

  # Minimum snapshots required before attempting forecasts
  MIN_SNAPSHOTS_REQUIRED = 100

  def perform
    logger.info "[ForecastJob] Starting forecast generation..."

    # Check if we have enough historical data
    unless sufficient_data?
      logger.info "[ForecastJob] Insufficient historical data, skipping forecasts"
      return
    end

    results = { generated: 0, validated: 0, errors: [] }

    # Generate forecasts for each configured asset
    Settings.assets.to_a.each do |symbol|
      generate_forecasts_for(symbol, results)
      validate_forecasts_for(symbol, results)
    end

    log_results(results)
  end

  private

  def sufficient_data?
    # Check if we have enough snapshots for at least one asset
    Settings.assets.to_a.any? do |symbol|
      MarketSnapshot.for_symbol(symbol).count >= MIN_SNAPSHOTS_REQUIRED
    end
  end

  def generate_forecasts_for(symbol, results)
    predictor = Forecasting::PricePredictor.new(symbol)
    forecasts = predictor.predict_all_timeframes

    forecasts.each do |timeframe, forecast|
      if forecast
        results[:generated] += 1
        logger.info "[ForecastJob] #{symbol} #{timeframe}: $#{forecast.current_price.round(2)} → $#{forecast.predicted_price.round(2)} (#{forecast.direction})"
      end
    end
  rescue StandardError => e
    results[:errors] << "#{symbol}: #{e.message}"
    logger.error "[ForecastJob] Error generating forecasts for #{symbol}: #{e.message}"
  end

  def validate_forecasts_for(symbol, results)
    predictor = Forecasting::PricePredictor.new(symbol)
    validation = predictor.validate_past_forecasts

    results[:validated] += validation[:validated]
    results[:errors].concat(validation[:errors]) if validation[:errors].any?
  rescue StandardError => e
    results[:errors] << "Validation #{symbol}: #{e.message}"
    logger.error "[ForecastJob] Error validating forecasts for #{symbol}: #{e.message}"
  end

  def log_results(results)
    logger.info "[ForecastJob] Complete: #{results[:generated]} generated, #{results[:validated]} validated"
    if results[:errors].any?
      logger.warn "[ForecastJob] Errors: #{results[:errors].join('; ')}"
    end
  end
end
