# frozen_string_literal: true

require "rails_helper"

RSpec.describe RiskMonitoringJob, type: :job do
  let(:stop_loss_manager) { instance_double(Risk::StopLossManager) }
  let(:circuit_breaker) { instance_double(Risk::CircuitBreaker) }

  before do
    allow(Risk::StopLossManager).to receive(:new).and_return(stop_loss_manager)
    allow(Risk::CircuitBreaker).to receive(:new).and_return(circuit_breaker)
    allow(stop_loss_manager).to receive(:check_all_positions).and_return({
      triggered: [],
      checked: 0,
      skipped: 0
    })
    allow(circuit_breaker).to receive(:check_and_update!)
    allow(circuit_breaker).to receive(:status).and_return({
      trading_allowed: true,
      daily_loss: 0,
      consecutive_losses: 0,
      triggered: false
    })
  end

  describe "#perform" do
    it "checks all positions for SL/TP triggers" do
      expect(stop_loss_manager).to receive(:check_all_positions)
      described_class.new.perform
    end

    it "updates circuit breaker metrics" do
      expect(circuit_breaker).to receive(:check_and_update!)
      described_class.new.perform
    end

    it "returns monitoring results" do
      result = described_class.new.perform

      expect(result).to include(:stop_loss_results, :circuit_breaker_status)
    end

    context "when SL/TP triggers occur" do
      before do
        allow(stop_loss_manager).to receive(:check_all_positions).and_return({
          triggered: [
            { position_id: 1, symbol: "BTC", trigger: "stop_loss" }
          ],
          checked: 3,
          skipped: 1
        })
      end

      it "logs the triggers" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Triggered 1 SL\/TP/)
        described_class.new.perform
      end
    end

    context "when circuit breaker is triggered" do
      before do
        allow(circuit_breaker).to receive(:status).and_return({
          trading_allowed: false,
          triggered: true,
          trigger_reason: "max_daily_loss"
        })
      end

      it "logs warning about circuit breaker" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:warn).with(/Circuit breaker active/)
        described_class.new.perform
      end
    end
  end

  describe "job configuration" do
    it "is queued in the default queue" do
      expect(described_class.queue_name).to eq("default")
    end
  end
end
