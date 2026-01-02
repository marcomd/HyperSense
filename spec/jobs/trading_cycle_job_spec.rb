# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingCycleJob, type: :job do
  let(:trading_cycle) { instance_double(TradingCycle) }
  let(:decision_hold) { create(:trading_decision, symbol: "BTC", operation: "hold") }
  let(:decision_open) { create(:trading_decision, symbol: "ETH", operation: "open") }
  let(:btc_volatility) do
    Indicators::VolatilityClassifier::Result.new(
      level: :medium,
      interval: 12,
      atr_value: 586.82,
      atr_percentage: 0.006
    )
  end
  let(:eth_volatility) do
    Indicators::VolatilityClassifier::Result.new(
      level: :high,
      interval: 6,
      atr_value: 25.67,
      atr_percentage: 0.0075
    )
  end

  before do
    allow(TradingCycle).to receive(:new).and_return(trading_cycle)
    allow(DashboardChannel).to receive(:broadcast_decision)
    # Mock per-symbol volatility classification
    allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol).with("BTC").and_return(btc_volatility)
    allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol).with("ETH").and_return(eth_volatility)
    allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol).with("SOL").and_return(btc_volatility)
    allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol).with("BNB").and_return(btc_volatility)
  end

  describe "#perform" do
    context "when cycle executes successfully" do
      let(:decisions) { [ decision_hold, decision_open ] }

      before do
        allow(trading_cycle).to receive(:execute).and_return(decisions)
      end

      it "creates a new trading cycle and executes" do
        expect(TradingCycle).to receive(:new).and_return(trading_cycle)
        expect(trading_cycle).to receive(:execute)

        described_class.new.perform
      end

      it "broadcasts each decision via ActionCable" do
        decisions.each do |decision|
          expect(DashboardChannel).to receive(:broadcast_decision).with(decision)
        end

        described_class.new.perform
      end

      it "returns the decisions" do
        result = described_class.new.perform

        expect(result).to eq(decisions)
      end

      it "logs the execution summary" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Trading cycle complete:.*decisions.*actionable/)

        described_class.new.perform
      end
    end

    context "when cycle returns empty decisions" do
      before do
        allow(trading_cycle).to receive(:execute).and_return([])
      end

      it "does not broadcast any decisions" do
        expect(DashboardChannel).not_to receive(:broadcast_decision)

        described_class.new.perform
      end

      it "returns empty array" do
        result = described_class.new.perform

        expect(result).to eq([])
      end
    end

    context "when broadcast fails" do
      before do
        allow(trading_cycle).to receive(:execute).and_return([ decision_hold ])
        allow(DashboardChannel).to receive(:broadcast_decision).and_raise(StandardError, "Broadcast error")
      end

      it "logs the error but does not fail" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:error).with(/Broadcast error/)

        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "is queued in the trading queue" do
      expect(described_class.queue_name).to eq("trading")
    end
  end

  describe "dynamic scheduling" do
    let(:decisions) { [ decision_hold ] }

    before do
      allow(trading_cycle).to receive(:execute).and_return(decisions)
    end

    it "schedules next job with highest volatility interval" do
      # ETH has highest volatility (interval: 6), so it determines schedule
      expect(described_class).to receive(:set).with(wait: 6.minutes).and_call_original

      described_class.new.perform
    end

    it "schedules ForecastJob 1 minute before next cycle" do
      # ETH has highest volatility (interval: 6), so ForecastJob runs at 5 minutes
      expect(ForecastJob).to receive(:set).with(wait: 5.minutes).and_call_original

      described_class.new.perform
    end

    context "with multiple symbols" do
      let(:decisions) { [ decision_hold, decision_open ] }

      it "updates each decision with its symbol-specific ATR percentage" do
        described_class.new.perform

        # BTC decision gets BTC-specific volatility
        decision_hold.reload
        expect(decision_hold.volatility_level).to eq("medium")
        expect(decision_hold.atr_value).to eq(0.006)
        # But interval uses aggregated (highest) volatility
        expect(decision_hold.next_cycle_interval).to eq(6)

        # ETH decision gets ETH-specific volatility
        decision_open.reload
        expect(decision_open.volatility_level).to eq("high")
        expect(decision_open.atr_value).to eq(0.0075)
        expect(decision_open.next_cycle_interval).to eq(6)
      end
    end

    it "always schedules next job even on error (ensure block)" do
      allow(trading_cycle).to receive(:execute).and_raise(StandardError, "Cycle error")
      # Still uses ETH's interval (6) because volatility calc succeeds in ensure block
      expect(described_class).to receive(:set).with(wait: 6.minutes).and_call_original

      expect { described_class.new.perform }.to raise_error(StandardError, "Cycle error")
    end

    context "with very high volatility" do
      let(:very_high_volatility) do
        Indicators::VolatilityClassifier::Result.new(
          level: :very_high,
          interval: 3,
          atr_value: 5.0,
          atr_percentage: 0.05
        )
      end

      before do
        # Override BTC to have very high volatility
        allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol).with("BTC")
          .and_return(very_high_volatility)
      end

      it "uses shorter interval for high volatility" do
        expect(described_class).to receive(:set).with(wait: 3.minutes).and_call_original

        described_class.new.perform
      end

      it "schedules ForecastJob 2 minutes before for 3-minute intervals" do
        # For 3-minute interval, ForecastJob runs at 2 minutes (3-1)
        expect(ForecastJob).to receive(:set).with(wait: 2.minutes).and_call_original

        described_class.new.perform
      end
    end

    context "with low volatility" do
      let(:low_volatility) do
        Indicators::VolatilityClassifier::Result.new(
          level: :low,
          interval: 25,
          atr_value: 0.5,
          atr_percentage: 0.005
        )
      end

      before do
        # Override all assets to have low volatility
        allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol)
          .and_return(low_volatility)
      end

      it "uses longer interval for low volatility" do
        expect(described_class).to receive(:set).with(wait: 25.minutes).and_call_original

        described_class.new.perform
      end
    end

    context "when volatility classification fails" do
      before do
        allow(Indicators::VolatilityClassifier).to receive(:classify_for_symbol)
          .and_raise(StandardError, "API error")
      end

      it "uses default interval" do
        expect(described_class).to receive(:set).with(wait: 12.minutes).and_call_original

        described_class.new.perform
      end
    end
  end
end
