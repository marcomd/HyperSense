# frozen_string_literal: true

require "rails_helper"

RSpec.describe ForecastJob, type: :job do
  let(:predictor) { instance_double(Forecasting::PricePredictor) }
  let(:forecast) { instance_double(Forecast, current_price: 97000.0, predicted_price: 98000.0, direction: "bullish") }

  before do
    allow(Forecasting::PricePredictor).to receive(:new).and_return(predictor)
    allow(predictor).to receive(:predict_all_timeframes).and_return({
      "1m" => forecast,
      "15m" => forecast,
      "1h" => forecast
    })
    allow(predictor).to receive(:validate_past_forecasts).and_return({
      validated: 2,
      errors: []
    })
  end

  describe "#perform" do
    context "when sufficient data exists" do
      before do
        # Create enough snapshots for at least one asset
        create_list(:market_snapshot, ForecastJob::MIN_SNAPSHOTS_REQUIRED, symbol: "BTC")
      end

      it "generates forecasts for each configured asset" do
        expect(Forecasting::PricePredictor).to receive(:new).with("BTC").and_return(predictor)
        expect(predictor).to receive(:predict_all_timeframes)

        described_class.new.perform
      end

      it "validates past forecasts for each asset" do
        expect(predictor).to receive(:validate_past_forecasts)

        described_class.new.perform
      end

      it "logs generation results" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Complete:.*generated/)

        described_class.new.perform
      end
    end

    context "when insufficient data exists" do
      it "skips forecast generation" do
        expect(Forecasting::PricePredictor).not_to receive(:new)

        described_class.new.perform
      end

      it "logs that data is insufficient" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Insufficient historical data/)

        described_class.new.perform
      end
    end

    context "when forecast generation fails" do
      before do
        create_list(:market_snapshot, ForecastJob::MIN_SNAPSHOTS_REQUIRED, symbol: "BTC")
        allow(predictor).to receive(:predict_all_timeframes).and_raise(StandardError, "Prophet error")
      end

      it "logs the error and continues" do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).to receive(:error).with(/Error generating forecasts/).at_least(:once)

        described_class.new.perform
      end
    end

    context "when validation fails" do
      before do
        create_list(:market_snapshot, ForecastJob::MIN_SNAPSHOTS_REQUIRED, symbol: "BTC")
        allow(predictor).to receive(:validate_past_forecasts).and_raise(StandardError, "Validation error")
      end

      it "logs the error and continues" do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).to receive(:error).with(/Error validating forecasts/).at_least(:once)

        described_class.new.perform
      end
    end
  end

  describe "job configuration" do
    it "is queued in the analysis queue" do
      expect(described_class.queue_name).to eq("analysis")
    end
  end

  describe "constants" do
    it "defines MIN_SNAPSHOTS_REQUIRED" do
      expect(ForecastJob::MIN_SNAPSHOTS_REQUIRED).to eq(100)
    end
  end
end
