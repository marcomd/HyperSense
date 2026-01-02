# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarketSnapshot do
  describe "validations" do
    it "is valid with valid attributes" do
      snapshot = build(:market_snapshot)
      expect(snapshot).to be_valid
    end

    it "requires symbol" do
      snapshot = build(:market_snapshot, symbol: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:symbol]).to include("can't be blank")
    end

    it "requires price" do
      snapshot = build(:market_snapshot, price: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:price]).to include("can't be blank")
    end

    it "requires price to be greater than 0" do
      snapshot = build(:market_snapshot, price: 0)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:price]).to include("must be greater than 0")
    end

    it "requires captured_at" do
      snapshot = build(:market_snapshot, captured_at: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:captured_at]).to include("can't be blank")
    end
  end

  describe "scopes" do
    describe ".for_symbol" do
      it "returns snapshots for the specified symbol" do
        btc = create(:market_snapshot, symbol: "BTC")
        _eth = create(:market_snapshot, :eth, captured_at: 1.minute.ago)

        expect(MarketSnapshot.for_symbol("BTC")).to contain_exactly(btc)
      end
    end

    describe ".recent" do
      it "orders by captured_at descending" do
        older = create(:market_snapshot, captured_at: 2.hours.ago)
        newer = create(:market_snapshot, captured_at: 1.hour.ago)

        expect(MarketSnapshot.recent.first).to eq(newer)
        expect(MarketSnapshot.recent.last).to eq(older)
      end
    end

    describe ".last_hours" do
      it "returns snapshots from the last n hours" do
        recent = create(:market_snapshot, captured_at: 30.minutes.ago)
        _old = create(:market_snapshot, captured_at: 3.hours.ago)

        expect(MarketSnapshot.last_hours(1)).to contain_exactly(recent)
      end
    end
  end

  describe ".latest_for" do
    it "returns the most recent snapshot for a symbol" do
      _older = create(:market_snapshot, symbol: "BTC", captured_at: 2.hours.ago)
      newer = create(:market_snapshot, symbol: "BTC", captured_at: 1.hour.ago)

      expect(MarketSnapshot.latest_for("BTC")).to eq(newer)
    end

    it "returns nil when no snapshots exist for symbol" do
      expect(MarketSnapshot.latest_for("UNKNOWN")).to be_nil
    end
  end

  describe "#indicator" do
    it "returns indicator value by name" do
      snapshot = build(:market_snapshot)
      expect(snapshot.indicator("rsi_14")).to eq(62.5)
      expect(snapshot.indicator("ema_20")).to eq(96_500)
    end

    it "returns nil for missing indicator" do
      snapshot = build(:market_snapshot, indicators: {})
      expect(snapshot.indicator("rsi_14")).to be_nil
    end

    it "accepts symbol keys" do
      snapshot = build(:market_snapshot)
      expect(snapshot.indicator(:rsi_14)).to eq(62.5)
    end
  end

  describe "#above_ema?" do
    it "returns true when price is above EMA" do
      snapshot = build(:market_snapshot, price: 97_000, indicators: { "ema_50" => 95_000 })
      expect(snapshot.above_ema?(50)).to be true
    end

    it "returns false when price is below EMA" do
      snapshot = build(:market_snapshot, price: 94_000, indicators: { "ema_50" => 95_000 })
      expect(snapshot.above_ema?(50)).to be false
    end

    it "returns nil when EMA is unavailable" do
      snapshot = build(:market_snapshot, indicators: {})
      expect(snapshot.above_ema?(50)).to be_nil
    end
  end

  describe "#rsi_signal" do
    it "returns :oversold when RSI < 30" do
      snapshot = build(:market_snapshot, :oversold)
      expect(snapshot.rsi_signal).to eq(:oversold)
    end

    it "returns :overbought when RSI > 70" do
      snapshot = build(:market_snapshot, :overbought)
      expect(snapshot.rsi_signal).to eq(:overbought)
    end

    it "returns :neutral when RSI is between 30 and 70" do
      snapshot = build(:market_snapshot)
      expect(snapshot.rsi_signal).to eq(:neutral)
    end

    it "returns nil when RSI is unavailable" do
      snapshot = build(:market_snapshot, indicators: {})
      expect(snapshot.rsi_signal).to be_nil
    end
  end

  describe "#macd_signal" do
    it "returns :bullish when histogram is positive" do
      snapshot = build(:market_snapshot)
      expect(snapshot.macd_signal).to eq(:bullish)
    end

    it "returns :bearish when histogram is negative" do
      snapshot = build(:market_snapshot, :oversold)
      expect(snapshot.macd_signal).to eq(:bearish)
    end

    it "returns nil when MACD is unavailable" do
      snapshot = build(:market_snapshot, indicators: {})
      expect(snapshot.macd_signal).to be_nil
    end
  end

  describe "#atr_signal" do
    it "returns :low_volatility when ATR < 1% of price" do
      snapshot = build(:market_snapshot, :low_volatility)
      expect(snapshot.atr_signal).to eq(:low_volatility)
    end

    it "returns :normal_volatility when ATR is 1-2% of price" do
      snapshot = build(:market_snapshot, :normal_volatility)
      expect(snapshot.atr_signal).to eq(:normal_volatility)
    end

    it "returns :high_volatility when ATR is 2-3% of price" do
      snapshot = build(:market_snapshot, :high_volatility)
      expect(snapshot.atr_signal).to eq(:high_volatility)
    end

    it "returns :very_high_volatility when ATR >= 3% of price" do
      snapshot = build(:market_snapshot, :very_high_volatility)
      expect(snapshot.atr_signal).to eq(:very_high_volatility)
    end

    it "returns nil when ATR is unavailable" do
      snapshot = build(:market_snapshot, indicators: {})
      expect(snapshot.atr_signal).to be_nil
    end

    it "returns nil when price is zero" do
      snapshot = build(:market_snapshot, price: 0.001, indicators: { "atr_14" => 100 })
      # Price validation will fail, but we can test the method directly
      snapshot.price = 0
      expect(snapshot.atr_signal).to be_nil
    end

    context "boundary conditions" do
      it "returns :low_volatility at exactly 0.99% ATR" do
        snapshot = build(:market_snapshot, price: 100_000, indicators: { "atr_14" => 990 })
        expect(snapshot.atr_signal).to eq(:low_volatility)
      end

      it "returns :normal_volatility at exactly 1% ATR" do
        snapshot = build(:market_snapshot, price: 100_000, indicators: { "atr_14" => 1_000 })
        expect(snapshot.atr_signal).to eq(:normal_volatility)
      end

      it "returns :high_volatility at exactly 2% ATR" do
        snapshot = build(:market_snapshot, price: 100_000, indicators: { "atr_14" => 2_000 })
        expect(snapshot.atr_signal).to eq(:high_volatility)
      end

      it "returns :very_high_volatility at exactly 3% ATR" do
        snapshot = build(:market_snapshot, price: 100_000, indicators: { "atr_14" => 3_000 })
        expect(snapshot.atr_signal).to eq(:very_high_volatility)
      end
    end
  end
end
