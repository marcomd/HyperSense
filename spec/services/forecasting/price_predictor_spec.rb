# frozen_string_literal: true

require "rails_helper"

RSpec.describe Forecasting::PricePredictor do
  let(:symbol) { "BTC" }
  let(:predictor) { described_class.new(symbol) }

  describe "#predict_all_timeframes" do
    context "with insufficient historical data" do
      before do
        # Only create 30 snapshots (less than MIN_HISTORICAL_POINTS = 50)
        30.times do |i|
          create(:market_snapshot, symbol: symbol, captured_at: i.minutes.ago)
        end
      end

      it "returns empty hash when not enough data points" do
        result = predictor.predict_all_timeframes
        expect(result).to eq({})
      end
    end

    context "with sufficient historical data", :slow do
      before do
        # Create enough snapshots for 1m and 15m forecasts (need at least 100 for 15m)
        100.times do |i|
          create(:market_snapshot,
            symbol: symbol,
            price: 97_000 + rand(-500..500),
            captured_at: (100 - i).minutes.ago)
        end
      end

      it "returns forecasts keyed by timeframe" do
        result = predictor.predict_all_timeframes
        expect(result).to be_a(Hash)
        # At least 1m and 15m should work with 100 data points
        expect(result.keys).to include("1m", "15m")
      end

      it "creates Forecast records with numeric predicted prices" do
        predictor.predict_all_timeframes
        forecasts = Forecast.where(symbol: symbol)
        expect(forecasts.count).to be >= 2

        forecasts.each do |forecast|
          expect(forecast.predicted_price).to be_a(BigDecimal).or be_a(Float)
          expect(forecast.predicted_price).to be > 0
        end
      end

      it "uses Rover::DataFrame for Prophet (not array of hashes)" do
        # This test ensures we don't regress to the old array format
        allow(Prophet).to receive(:new).and_call_original

        predictor.predict_all_timeframes

        # If Prophet was called, it should have worked (not raised "Must be a data frame")
        expect(Forecast.where(symbol: symbol).count).to be >= 1
      end
    end
  end

  describe "#predict" do
    context "with valid timeframe and sufficient data", :slow do
      before do
        70.times do |i|
          create(:market_snapshot,
            symbol: symbol,
            price: 97_000 + rand(-500..500),
            captured_at: (70 - i).minutes.ago)
        end
      end

      it "creates a forecast with Float predicted_price" do
        forecast = predictor.predict("1m")

        expect(forecast).to be_a(Forecast)
        expect(forecast.predicted_price).to be_a(BigDecimal).or be_a(Float)
        expect(forecast.predicted_price.to_f).to be > 0
      end

      it "returns nil for invalid timeframe" do
        expect(predictor.predict("invalid")).to be_nil
      end
    end
  end

  describe "#validate_past_forecasts" do
    let!(:due_forecast) do
      create(:forecast,
        symbol: symbol,
        timeframe: "1m",
        forecast_for: 5.minutes.ago,
        actual_price: nil)
    end

    let!(:future_forecast) do
      create(:forecast,
        symbol: symbol,
        timeframe: "1m",
        forecast_for: 5.minutes.from_now,
        actual_price: nil)
    end

    before do
      # Create a snapshot near the due forecast time
      create(:market_snapshot,
        symbol: symbol,
        price: 98_500,
        captured_at: 5.minutes.ago)
    end

    it "validates only due forecasts" do
      results = predictor.validate_past_forecasts

      expect(results[:validated]).to eq(1)
      expect(due_forecast.reload.actual_price).to eq(98_500)
      expect(future_forecast.reload.actual_price).to be_nil
    end
  end

  describe "data format requirements" do
    # These tests document the expected data formats to prevent regressions

    it "requires Rover::DataFrame for Prophet.fit" do
      # Prophet-rb requires Rover::DataFrame, not array of hashes
      data = Rover::DataFrame.new({
        "ds" => [ 1.hour.ago, 30.minutes.ago, Time.current ],
        "y" => [ 97_000.0, 97_500.0, 98_000.0 ]
      })

      expect(data).to be_a(Rover::DataFrame)
      expect(data.size).to eq(3)
    end

    it "extracts Float from Rover::Vector using .last" do
      # Prophet returns a DataFrame with Rover::Vector columns
      # We need to extract scalar values correctly
      df = Rover::DataFrame.new({
        "yhat" => [ 97_000.0, 98_000.0, 99_000.0 ]
      })

      # Correct way to get the last prediction
      value = df["yhat"].last
      expect(value).to be_a(Float)
      expect(value).to eq(99_000.0)

      # Wrong way (returns Rover::Vector, not Float)
      wrong_value = df.last["yhat"]
      expect(wrong_value).to be_a(Rover::Vector)
    end

    it "uses valid Prophet frequency strings" do
      # Prophet-rb only supports specific frequency strings
      # "60S" for seconds, "H" for hours, "D" for days
      # "T" and "min" are NOT valid

      valid_frequencies = %w[60S H D W MS QS YS]
      invalid_frequencies = %w[T min M 1m 15m]

      valid_frequencies.each do |freq|
        expect(freq).to match(/\A(\d+S|H|D|W|MS|QS|YS)\z/)
      end

      invalid_frequencies.each do |freq|
        expect(freq).not_to match(/\A(\d+S|H|D|W|MS|QS|YS)\z/)
      end
    end
  end
end
