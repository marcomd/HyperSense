# frozen_string_literal: true

require "spec_helper"
require_relative "../../../app/services/indicators/calculator"

RSpec.describe Indicators::Calculator do
  subject(:calculator) { described_class.new }

  describe "#ema" do
    let(:prices) { [22, 23, 24, 25, 26, 27, 28, 29, 30, 31] }

    it "calculates EMA correctly" do
      result = calculator.ema(prices, 5)
      expect(result).to be_a(Float)
      expect(result).to be_between(27, 31)
    end

    it "returns nil when not enough data" do
      expect(calculator.ema([1, 2, 3], 5)).to be_nil
    end

    it "weights recent prices more heavily" do
      prices_up = [10, 11, 12, 13, 14, 15, 16, 17, 18, 20]
      prices_flat = [10, 10, 10, 10, 10, 10, 10, 10, 10, 20]

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
      expect(calculator.rsi([1, 2, 3], 14)).to be_nil
    end

    context "with mixed gains and losses" do
      let(:prices) { [44, 44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89, 46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22] }

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
      expect(calculator.macd([1, 2, 3])).to be_nil
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
  end
end
