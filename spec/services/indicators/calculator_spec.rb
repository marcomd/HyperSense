# frozen_string_literal: true

require "spec_helper"
require_relative "../../../app/services/indicators/calculator"

RSpec.describe Indicators::Calculator do
  subject(:calculator) { described_class.new }

  describe "#ema" do
    let(:prices) { [ 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 ] }

    it "calculates EMA correctly" do
      result = calculator.ema(prices, 5)
      expect(result).to be_a(Float)
      expect(result).to be_between(27, 31)
    end

    it "returns nil when not enough data" do
      expect(calculator.ema([ 1, 2, 3 ], 5)).to be_nil
    end

    it "weights recent prices more heavily" do
      prices_up = [ 10, 11, 12, 13, 14, 15, 16, 17, 18, 20 ]
      prices_flat = [ 10, 10, 10, 10, 10, 10, 10, 10, 10, 20 ]

      ema_up = calculator.ema(prices_up, 5)
      ema_flat = calculator.ema(prices_flat, 5)

      expect(ema_up).to be > ema_flat
    end
  end

  describe "#rsi" do
    it "returns values between 0 and 100" do
      prices = (1..30).to_a
      result = calculator.rsi(prices, 14)
      expect(result).to be_between(0, 100)
    end

    it "returns 100 when all gains" do
      prices = (1..20).to_a
      result = calculator.rsi(prices, 14)
      expect(result).to eq(100.0)
    end

    it "returns nil when not enough data" do
      expect(calculator.rsi([ 1, 2, 3 ], 14)).to be_nil
    end

    context "with mixed gains and losses" do
      let(:prices) { [ 44, 44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89, 46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22 ] }

      it "calculates RSI within expected range" do
        result = calculator.rsi(prices, 14)
        expect(result).to be_between(40, 80)
      end
    end
  end

  describe "#macd" do
    let(:prices) { (1..50).map { |i| 100 + Math.sin(i * 0.3) * 10 } }

    it "returns a hash with macd, signal, and histogram" do
      result = calculator.macd(prices)
      expect(result).to include(:macd, :signal, :histogram)
    end

    it "returns nil when not enough data" do
      expect(calculator.macd([ 1, 2, 3 ])).to be_nil
    end
  end

  describe "#pivot_points" do
    it "calculates pivot points correctly" do
      result = calculator.pivot_points(110, 100, 105)

      expect(result[:pp]).to eq(105.0)
      expect(result[:r1]).to eq(110.0)
      expect(result[:r2]).to eq(115.0)
      expect(result[:s1]).to eq(100.0)
      expect(result[:s2]).to eq(95.0)
    end
  end

  describe "#atr" do
    # Sample OHLC candles with known volatility patterns
    let(:candles) do
      [
        { high: 100, low: 95, close: 98 },
        { high: 102, low: 97, close: 100 },
        { high: 104, low: 99, close: 101 },
        { high: 103, low: 98, close: 99 },
        { high: 105, low: 100, close: 103 },
        { high: 106, low: 101, close: 104 },
        { high: 108, low: 102, close: 105 },
        { high: 107, low: 100, close: 102 },
        { high: 109, low: 103, close: 107 },
        { high: 110, low: 104, close: 108 },
        { high: 112, low: 106, close: 110 },
        { high: 111, low: 105, close: 107 },
        { high: 113, low: 108, close: 111 },
        { high: 115, low: 109, close: 113 },
        { high: 114, low: 107, close: 110 }
      ]
    end

    it "calculates ATR correctly" do
      result = calculator.atr(candles, 14)
      expect(result).to be_a(Float)
      # ATR should be positive and reasonable given the price range
      expect(result).to be > 0
      expect(result).to be < 20
    end

    it "returns nil when insufficient data" do
      short_candles = candles.first(10)
      expect(calculator.atr(short_candles, 14)).to be_nil
    end

    it "returns nil when exactly period candles (needs period + 1)" do
      exact_candles = candles.first(14)
      expect(calculator.atr(exact_candles, 14)).to be_nil
    end

    it "uses EMA smoothing for True Range values" do
      result = calculator.atr(candles, 5)
      # With shorter period, ATR should react more to recent volatility
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end

    context "with high volatility candles" do
      let(:high_volatility_candles) do
        [
          { high: 100, low: 80, close: 90 },
          { high: 110, low: 85, close: 105 },
          { high: 115, low: 90, close: 95 },
          { high: 120, low: 88, close: 115 },
          { high: 125, low: 95, close: 100 },
          { high: 130, low: 90, close: 120 }
        ]
      end

      let(:low_volatility_candles) do
        [
          { high: 101, low: 99, close: 100 },
          { high: 102, low: 100, close: 101 },
          { high: 102, low: 100, close: 101 },
          { high: 103, low: 101, close: 102 },
          { high: 103, low: 101, close: 102 },
          { high: 104, low: 102, close: 103 }
        ]
      end

      it "returns higher ATR for volatile markets" do
        high_atr = calculator.atr(high_volatility_candles, 5)
        low_atr = calculator.atr(low_volatility_candles, 5)

        expect(high_atr).to be > low_atr
      end
    end

    context "with gaps (true range considers previous close)" do
      let(:gap_candles) do
        [
          { high: 100, low: 95, close: 98 },
          { high: 110, low: 105, close: 108 }, # Gap up from 98 to 105
          { high: 112, low: 106, close: 110 }
        ]
      end

      it "accounts for gaps in true range calculation" do
        # True range for candle 2 should be max(110-105=5, |110-98|=12, |105-98|=7) = 12
        result = calculator.atr(gap_candles, 2)
        expect(result).to be > 5 # Should be higher than just high-low range
      end
    end
  end

  describe "#calculate_all" do
    let(:prices) { (1..150).map { |i| 100 + Math.sin(i * 0.1) * 5 } }

    it "returns all indicators" do
      result = calculator.calculate_all(prices, high: 110, low: 95)

      expect(result).to include(
        :ema_20,
        :ema_50,
        :ema_100,
        :rsi_14,
        :macd,
        :pivot_points
      )
    end

    context "with candles provided" do
      let(:candles) do
        (1..20).map do |i|
          base = 100 + Math.sin(i * 0.1) * 5
          { high: base + 2, low: base - 2, close: base }
        end
      end

      it "includes ATR when candles are provided" do
        result = calculator.calculate_all(prices, high: 110, low: 95, candles: candles)

        expect(result).to include(:atr_14)
        expect(result[:atr_14]).to be_a(Float)
      end

      it "returns nil for ATR when candles are not provided" do
        result = calculator.calculate_all(prices, high: 110, low: 95)

        expect(result[:atr_14]).to be_nil
      end
    end
  end
end
