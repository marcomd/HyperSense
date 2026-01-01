# frozen_string_literal: true

require "rails_helper"

RSpec.describe BootstrapTradingCycleJob, type: :job do
  describe "#perform" do
    let(:job) { described_class.new }

    context "when no TradingCycleJob is scheduled" do
      before do
        allow(job).to receive(:trading_cycle_scheduled?).and_return(false)
      end

      it "schedules a TradingCycleJob" do
        expect(TradingCycleJob).to receive(:perform_later)

        job.perform
      end

      it "logs that it is starting the chain" do
        allow(TradingCycleJob).to receive(:perform_later)
        expect(Rails.logger).to receive(:info).with(/No trading cycle found/)
        expect(Rails.logger).to receive(:info).with(/chain started/)

        job.perform
      end
    end

    context "when TradingCycleJob is already scheduled" do
      before do
        allow(job).to receive(:trading_cycle_scheduled?).and_return(true)
      end

      it "does not schedule another TradingCycleJob" do
        expect(TradingCycleJob).not_to receive(:perform_later)

        job.perform
      end

      it "logs that trading cycle is already scheduled" do
        expect(Rails.logger).to receive(:info).with(/already scheduled/)

        job.perform
      end
    end
  end

  describe "job configuration" do
    it "is queued in the trading queue" do
      expect(described_class.queue_name).to eq("trading")
    end
  end
end
