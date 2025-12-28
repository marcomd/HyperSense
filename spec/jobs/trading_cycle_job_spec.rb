# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingCycleJob, type: :job do
  let(:trading_cycle) { instance_double(TradingCycle) }
  let(:decision_hold) { build(:trading_decision, operation: "hold") }
  let(:decision_open) { build(:trading_decision, operation: "open") }

  before do
    allow(TradingCycle).to receive(:new).and_return(trading_cycle)
    allow(DashboardChannel).to receive(:broadcast_decision)
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
end
