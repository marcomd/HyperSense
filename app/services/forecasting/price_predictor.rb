# frozen_string_literal: true

require "prophet"
require "rover"

module Forecasting
  # Price prediction service using Meta's Prophet
  #
  # Uses historical price data from MarketSnapshot to train Prophet models
  # and generate predictions for multiple timeframes (1m, 15m, 1h).
  #
  # @example Generate predictions for BTC
  #   predictor = Forecasting::PricePredictor.new("BTC")
  #   forecasts = predictor.predict_all_timeframes
  #   # => { "1m" => Forecast, "15m" => Forecast, "1h" => Forecast }
  #
  class PricePredictor
    # Timeframe configurations
    # - period: Prophet prediction period name
    # - minutes: minutes ahead to predict
    # - min_data_points: minimum historical data points needed
    TIMEFRAMES = {
      "1m" => { period: "T", minutes: 1, min_data_points: 60 },
      "15m" => { period: "15T", minutes: 15, min_data_points: 100 },
      "1h" => { period: "H", minutes: 60, min_data_points: 150 }
    }.freeze

    # Minimum data points required for any prediction
    MIN_HISTORICAL_POINTS = 50

    def initialize(symbol)
      @symbol = symbol
      @logger = Rails.logger
    end

    # Generate predictions for all timeframes
    # @return [Hash<String, Forecast>] Forecasts keyed by timeframe
    def predict_all_timeframes
      historical_data = fetch_historical_data
      return {} if historical_data.empty?

      current_price = historical_data.last[:price]

      TIMEFRAMES.to_h do |timeframe, config|
        forecast = predict_for_timeframe(timeframe, historical_data, current_price, config)
        [ timeframe, forecast ]
      end.compact
    end

    # Generate prediction for a specific timeframe
    # @param timeframe [String] "1m", "15m", or "1h"
    # @return [Forecast, nil] Created forecast or nil if insufficient data
    def predict(timeframe)
      config = TIMEFRAMES[timeframe]
      return nil unless config

      historical_data = fetch_historical_data
      return nil if historical_data.empty?

      current_price = historical_data.last[:price]
      predict_for_timeframe(timeframe, historical_data, current_price, config)
    end

    # Validate past forecasts that are now due
    # @return [Hash] Validation results
    def validate_past_forecasts
      due_forecasts = Forecast.for_symbol(@symbol).due_for_validation
      results = { validated: 0, failed: 0, errors: [] }

      due_forecasts.find_each do |forecast|
        actual_price = fetch_price_at(forecast.forecast_for)
        if actual_price
          forecast.validate_with_actual!(actual_price)
          results[:validated] += 1
        else
          results[:failed] += 1
          results[:errors] << "No price data for #{forecast.forecast_for}"
        end
      rescue StandardError => e
        results[:failed] += 1
        results[:errors] << e.message
      end

      results
    end

    private

    def predict_for_timeframe(timeframe, historical_data, current_price, config)
      return if historical_data.size < config[:min_data_points]

      # Prepare data for Prophet (requires Rover::DataFrame with 'ds' and 'y' columns)
      prophet_data = Rover::DataFrame.new({
        "ds" => historical_data.map { |p| p[:timestamp] },
        "y" => historical_data.map { |p| p[:price] }
      })

      # Train Prophet model
      model = Prophet.new(
        yearly_seasonality: false,
        weekly_seasonality: true,
        daily_seasonality: true,
        changepoint_prior_scale: 0.05
      )
      model.fit(prophet_data)

      # Generate future prediction
      forecast_time = Time.current + config[:minutes].minutes
      future = model.make_future_dataframe(periods: config[:minutes], freq: "60S", include_history: false)
      prediction = model.predict(future)

      # Get the predicted value (last value of yhat column)
      predicted_price = prediction["yhat"].last

      # Create and save forecast record
      create_forecast(timeframe, current_price, predicted_price, forecast_time)
    rescue StandardError => e
      @logger.error "[PricePredictor] Error predicting #{@symbol} #{timeframe}: #{e.message}"
      nil
    end

    def create_forecast(timeframe, current_price, predicted_price, forecast_for)
      Forecast.create!(
        symbol: @symbol,
        timeframe: timeframe,
        current_price: current_price,
        predicted_price: predicted_price,
        forecast_for: forecast_for
      )
    end

    def fetch_historical_data
      # Get price data from MarketSnapshot (last 24 hours, 1 per minute)
      snapshots = MarketSnapshot.for_symbol(@symbol)
                                .where("captured_at >= ?", 24.hours.ago)
                                .order(captured_at: :asc)

      return [] if snapshots.count < MIN_HISTORICAL_POINTS

      snapshots.map do |snapshot|
        {
          timestamp: snapshot.captured_at,
          price: snapshot.price.to_f
        }
      end
    end

    # Fetch the price at a specific target time
    #
    # Finds the closest snapshot within a 4-minute window around the target time.
    # Uses parameterized SQL to avoid injection vulnerabilities.
    #
    # @param target_time [Time] The target timestamp to fetch price for
    # @return [Float, nil] The price at that time, or nil if no snapshot found
    def fetch_price_at(target_time)
      # Find the closest snapshot to the target time within a 4-minute window
      snapshots = MarketSnapshot.for_symbol(@symbol)
                                .where(captured_at: (target_time - 2.minutes)..(target_time + 2.minutes))
                                .to_a

      return nil if snapshots.empty?

      # Find the snapshot closest to target_time (in-memory sort to avoid SQL injection)
      closest = snapshots.min_by { |s| (s.captured_at - target_time).abs }
      closest&.price&.to_f
    end
  end
end
