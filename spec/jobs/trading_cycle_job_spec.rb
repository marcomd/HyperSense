# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingCycleJob, type: :job do
  let(:trading_cycle) { instance_double(TradingCycle) }
  let(:decision_hold) { create(:trading_decision, operation: "hold") }
  let(:decision_open) { create(:trading_decision, operation: "open") }
  let(:volatility_result) do
    Indicators::VolatilityClassifier::Result.new(
      level: :medium,
      interval: 12,
      atr_value: 1.5,
      atr_percentage: 0.015
    )
  end

  before do
    allow(TradingCycle).to receive(:new).and_return(trading_cycle)
    allow(DashboardChannel).to receive(:broadcast_decision)
    allow(Indicators::VolatilityClassifier).to receive(:classify_all_assets).and_return(volatility_result)
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

    it "schedules next job with volatility-based interval" do
      expect(described_class).to receive(:set).with(wait: 12.minutes).and_call_original

      described_class.new.perform
    end

    it "schedules ForecastJob 1 minute before next cycle" do
      expect(ForecastJob).to receive(:set).with(wait: 11.minutes).and_call_original

      described_class.new.perform
    end

    it "updates decisions with volatility data" do
      described_class.new.perform

      decision_hold.reload
      expect(decision_hold.volatility_level).to eq("medium")
      expect(decision_hold.atr_value).to eq(1.5)
      expect(decision_hold.next_cycle_interval).to eq(12)
    end

    it "always schedules next job even on error (ensure block)" do
      allow(trading_cycle).to receive(:execute).and_raise(StandardError, "Cycle error")
      expect(described_class).to receive(:set).with(wait: 12.minutes).and_call_original

      expect { described_class.new.perform }.to raise_error(StandardError, "Cycle error")
    end

    context "with very high volatility" do
      let(:high_volatility_result) do
        Indicators::VolatilityClassifier::Result.new(
          level: :very_high,
          interval: 3,
          atr_value: 5.0,
          atr_percentage: 0.05
        )
      end

      before do
        allow(Indicators::VolatilityClassifier).to receive(:classify_all_assets)
          .and_return(high_volatility_result)
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
      let(:low_volatility_result) do
        Indicators::VolatilityClassifier::Result.new(
          level: :low,
          interval: 25,
          atr_value: 0.5,
          atr_percentage: 0.005
        )
      end

      before do
        allow(Indicators::VolatilityClassifier).to receive(:classify_all_assets)
          .and_return(low_volatility_result)
      end

      it "uses longer interval for low volatility" do
        expect(described_class).to receive(:set).with(wait: 25.minutes).and_call_original

        described_class.new.perform
      end
    end

    context "when volatility classification fails" do
      before do
        allow(Indicators::VolatilityClassifier).to receive(:classify_all_assets)
          .and_raise(StandardError, "API error")
      end

      it "uses default interval" do
        expect(described_class).to receive(:set).with(wait: 12.minutes).and_call_original

        described_class.new.perform
      end
    end
  end
end
