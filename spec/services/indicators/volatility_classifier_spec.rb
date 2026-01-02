# frozen_string_literal: true

require "rails_helper"

RSpec.describe Indicators::VolatilityClassifier do
  describe ".classify" do
    let(:current_price) { 100.0 }

    context "when ATR is very high (>= 3% of price)" do
      it "returns :very_high with 3 minute interval" do
        result = described_class.classify(3.5, current_price)

        expect(result.level).to eq(:very_high)
        expect(result.interval).to eq(3)
        expect(result.atr_value).to eq(3.5)
        expect(result.atr_percentage).to eq(0.035)
      end
    end

    context "when ATR is high (>= 2% but < 3% of price)" do
      it "returns :high with 6 minute interval" do
        result = described_class.classify(2.5, current_price)

        expect(result.level).to eq(:high)
        expect(result.interval).to eq(6)
        expect(result.atr_percentage).to eq(0.025)
      end
    end

    context "when ATR is medium (>= 1% but < 2% of price)" do
      it "returns :medium with 12 minute interval" do
        result = described_class.classify(1.5, current_price)

        expect(result.level).to eq(:medium)
        expect(result.interval).to eq(12)
        expect(result.atr_percentage).to eq(0.015)
      end
    end

    context "when ATR is low (< 1% of price)" do
      it "returns :low with 25 minute interval" do
        result = described_class.classify(0.5, current_price)

        expect(result.level).to eq(:low)
        expect(result.interval).to eq(25)
        expect(result.atr_percentage).to eq(0.005)
      end
    end

    context "with edge cases" do
      it "returns default result when ATR is nil" do
        result = described_class.classify(nil, current_price)

        expect(result.level).to eq(:medium)
        expect(result.interval).to eq(12)
        expect(result.atr_value).to be_nil
      end

      it "returns default result when price is nil" do
        result = described_class.classify(2.0, nil)

        expect(result.level).to eq(:medium)
        expect(result.interval).to eq(12)
      end

      it "returns default result when price is zero" do
        result = described_class.classify(2.0, 0)

        expect(result.level).to eq(:medium)
        expect(result.interval).to eq(12)
      end

      it "handles boundary values correctly (exactly at threshold)" do
        # Exactly 3% should be very_high
        result = described_class.classify(3.0, current_price)
        expect(result.level).to eq(:very_high)

        # Exactly 2% should be high
        result = described_class.classify(2.0, current_price)
        expect(result.level).to eq(:high)

        # Exactly 1% should be medium
        result = described_class.classify(1.0, current_price)
        expect(result.level).to eq(:medium)
      end
    end

    context "with custom thresholds" do
      let(:custom_thresholds) do
        { very_high: 0.05, high: 0.03, medium: 0.02 }
      end

      it "uses custom thresholds when provided" do
        # 2.5% should be medium with custom thresholds (>= 2%, < 3%)
        result = described_class.classify(2.5, current_price, thresholds: custom_thresholds)

        expect(result.level).to eq(:medium)
      end
    end
  end

  describe ".classify_for_symbol" do
    let(:mock_fetcher) { instance_double(DataIngestion::PriceFetcher) }
    let(:mock_calculator) { instance_double(Indicators::Calculator) }
    let(:candles) do
      (1..20).map do |i|
        { high: 100 + i, low: 95 + i, close: 98 + i }
      end
    end

    before do
      allow(DataIngestion::PriceFetcher).to receive(:new).and_return(mock_fetcher)
      allow(Indicators::Calculator).to receive(:new).and_return(mock_calculator)
    end

    it "fetches candles and calculates ATR for symbol" do
      allow(mock_fetcher).to receive(:fetch_klines)
        .with("BTC", interval: "1h", limit: 150)
        .and_return(candles)
      allow(mock_calculator).to receive(:atr)
        .with(candles, 14)
        .and_return(2.5)

      result = described_class.classify_for_symbol("BTC")

      # 2.5 / 118 (last candle close) = ~2.1%, which is :high
      expect(result.level).to eq(:high)
      expect(result.atr_value).to eq(2.5)
    end

    it "returns default medium on API error" do
      allow(mock_fetcher).to receive(:fetch_klines)
        .and_raise(StandardError, "API error")

      result = described_class.classify_for_symbol("BTC")

      expect(result.level).to eq(:medium)
      expect(result.interval).to eq(12)
    end
  end

  describe ".classify_all_assets" do
    before do
      allow(Settings).to receive(:assets).and_return(%w[BTC ETH SOL])
    end

    it "returns the highest volatility (most frequent interval) among all assets" do
      allow(described_class).to receive(:classify_for_symbol).with("BTC")
        .and_return(described_class::Result.new(level: :low, interval: 25, atr_value: 0.5, atr_percentage: 0.005))
      allow(described_class).to receive(:classify_for_symbol).with("ETH")
        .and_return(described_class::Result.new(level: :very_high, interval: 3, atr_value: 5.0, atr_percentage: 0.05))
      allow(described_class).to receive(:classify_for_symbol).with("SOL")
        .and_return(described_class::Result.new(level: :medium, interval: 12, atr_value: 1.5, atr_percentage: 0.015))

      result = described_class.classify_all_assets

      # Should return the highest volatility (ETH with 3 min interval)
      expect(result.level).to eq(:very_high)
      expect(result.interval).to eq(3)
    end

    it "returns medium when all assets have the same volatility" do
      medium_result = described_class::Result.new(level: :medium, interval: 12, atr_value: 1.5, atr_percentage: 0.015)
      allow(described_class).to receive(:classify_for_symbol).and_return(medium_result)

      result = described_class.classify_all_assets

      expect(result.level).to eq(:medium)
      expect(result.interval).to eq(12)
    end
  end

  describe "Result struct" do
    it "has the expected attributes" do
      result = described_class::Result.new(
        level: :high,
        interval: 6,
        atr_value: 2.5,
        atr_percentage: 0.025
      )

      expect(result.level).to eq(:high)
      expect(result.interval).to eq(6)
      expect(result.atr_value).to eq(2.5)
      expect(result.atr_percentage).to eq(0.025)
    end
  end
end
