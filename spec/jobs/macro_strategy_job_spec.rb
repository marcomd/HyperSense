# frozen_string_literal: true

require "rails_helper"

RSpec.describe MacroStrategyJob, type: :job do
  let(:agent) { instance_double(Reasoning::HighLevelAgent) }
  let(:strategy) { create(:macro_strategy) }

  before do
    allow(Reasoning::HighLevelAgent).to receive(:new).and_return(agent)
    allow(DashboardChannel).to receive(:broadcast_macro_strategy)
  end

  describe "#perform" do
    context "when analysis succeeds" do
      before do
        allow(agent).to receive(:analyze).and_return(strategy)
      end

      it "creates a new high-level agent and analyzes" do
        expect(Reasoning::HighLevelAgent).to receive(:new).and_return(agent)
        expect(agent).to receive(:analyze)

        described_class.new.perform
      end

      it "broadcasts the strategy via ActionCable" do
        expect(DashboardChannel).to receive(:broadcast_macro_strategy).with(strategy)

        described_class.new.perform
      end

      it "returns the created strategy" do
        result = described_class.new.perform

        expect(result).to eq(strategy)
      end

      it "logs the strategy details" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Created strategy:.*bias/)

        described_class.new.perform
      end
    end

    context "when analysis fails" do
      before do
        allow(agent).to receive(:analyze).and_return(nil)
      end

      it "does not broadcast via ActionCable" do
        expect(DashboardChannel).not_to receive(:broadcast_macro_strategy)

        described_class.new.perform
      end

      it "logs a warning" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:warn).with(/Failed to create strategy/)

        described_class.new.perform
      end

      it "returns nil" do
        result = described_class.new.perform

        expect(result).to be_nil
      end
    end
  end

  describe "job configuration" do
    it "is queued in the analysis queue" do
      expect(described_class.queue_name).to eq("analysis")
    end
  end
end
