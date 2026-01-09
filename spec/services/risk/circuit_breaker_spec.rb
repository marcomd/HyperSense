# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::CircuitBreaker do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:circuit_breaker) { described_class.new }

  before do
    # Use memory store for tests
    allow(Rails).to receive(:cache).and_return(memory_store)
    # Clean up trading modes
    TradingMode.delete_all
  end

  describe "#trading_allowed?" do
    context "when trading mode is enabled" do
      it "returns true" do
        create(:trading_mode, mode: "enabled")
        expect(circuit_breaker.trading_allowed?).to be true
      end
    end

    context "when trading mode is exit_only" do
      it "returns false" do
        create(:trading_mode, mode: "exit_only")
        expect(circuit_breaker.trading_allowed?).to be false
      end
    end

    context "when trading mode is blocked" do
      it "returns false" do
        create(:trading_mode, mode: "blocked")
        expect(circuit_breaker.trading_allowed?).to be false
      end
    end
  end

  describe "#record_loss" do
    it "increments consecutive losses" do
      expect { circuit_breaker.record_loss(100) }
        .to change { circuit_breaker.consecutive_losses }.from(0).to(1)
    end

    it "adds to daily loss total" do
      circuit_breaker.record_loss(100)
      circuit_breaker.record_loss(50)
      expect(circuit_breaker.daily_loss).to eq(150)
    end
  end

  describe "#record_win" do
    before do
      3.times { circuit_breaker.record_loss(50) }
    end

    it "resets consecutive losses" do
      expect { circuit_breaker.record_win(100) }
        .to change { circuit_breaker.consecutive_losses }.from(3).to(0)
    end

    it "does not affect daily loss total" do
      expect { circuit_breaker.record_win(100) }
        .not_to change { circuit_breaker.daily_loss }
    end
  end

  describe "#trigger!" do
    before do
      create(:trading_mode, mode: "enabled")
    end

    it "sets trading mode to exit_only" do
      circuit_breaker.trigger!("max_daily_loss")
      expect(TradingMode.current_mode).to eq("exit_only")
    end

    it "sets changed_by to circuit_breaker" do
      circuit_breaker.trigger!("max_daily_loss")
      expect(TradingMode.current.changed_by).to eq("circuit_breaker")
    end

    it "sets human-readable reason for max_daily_loss" do
      circuit_breaker.trigger!("max_daily_loss")
      expect(TradingMode.current.reason).to eq("Daily loss exceeded 5.0%")
    end

    it "sets human-readable reason for consecutive_losses" do
      circuit_breaker.trigger!("consecutive_losses")
      expect(TradingMode.current.reason).to eq("3 consecutive losing trades")
    end

    it "broadcasts trading mode update" do
      expect(DashboardChannel).to receive(:broadcast_trading_mode_update)
      circuit_breaker.trigger!("test")
    end
  end

  describe "#reset!" do
    before do
      circuit_breaker.record_loss(100)
      circuit_breaker.record_loss(50)
      circuit_breaker.trigger!("test")
    end

    it "clears loss tracking state" do
      circuit_breaker.reset!

      expect(circuit_breaker.daily_loss).to eq(0)
      expect(circuit_breaker.consecutive_losses).to eq(0)
    end

    it "resets trading mode to enabled" do
      circuit_breaker.reset!

      expect(TradingMode.current_mode).to eq("enabled")
      expect(TradingMode.current.changed_by).to eq("system")
      expect(TradingMode.current.reason).to be_nil
    end
  end

  describe "#check_and_update!" do
    before do
      create(:trading_mode, mode: "enabled")
      allow(circuit_breaker).to receive(:fetch_account_value).and_return(10_000)
    end

    context "when daily loss exceeds threshold" do
      before do
        circuit_breaker.record_loss(600) # 6% of $10,000
      end

      it "triggers circuit breaker" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be true
        expect(TradingMode.current_mode).to eq("exit_only")
      end
    end

    context "when consecutive losses exceed threshold" do
      before do
        4.times { circuit_breaker.record_loss(50) }
      end

      it "triggers circuit breaker" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be true
        expect(TradingMode.current_mode).to eq("exit_only")
      end
    end

    context "when within limits" do
      before do
        circuit_breaker.record_loss(100) # 1% loss, 1 consecutive
      end

      it "does not trigger" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be false
        expect(TradingMode.current_mode).to eq("enabled")
      end
    end

    context "when mode is already exit_only" do
      before do
        TradingMode.switch_to!("exit_only", changed_by: "dashboard")
        4.times { circuit_breaker.record_loss(50) } # Exceed threshold
      end

      it "does not re-trigger" do
        expect(circuit_breaker).not_to receive(:trigger!)
        circuit_breaker.check_and_update!
      end
    end

    context "when mode is blocked" do
      before do
        TradingMode.switch_to!("blocked", changed_by: "dashboard")
        4.times { circuit_breaker.record_loss(50) } # Exceed threshold
      end

      it "does not trigger" do
        expect(circuit_breaker).not_to receive(:trigger!)
        circuit_breaker.check_and_update!
      end
    end
  end

  describe "#triggered?" do
    before do
      create(:trading_mode, mode: "enabled")
    end

    it "returns false when mode is enabled" do
      expect(circuit_breaker.triggered?).to be false
    end

    it "returns true when mode is exit_only and changed_by is circuit_breaker" do
      TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker")
      expect(circuit_breaker.triggered?).to be true
    end

    it "returns false when mode is exit_only but changed_by is dashboard" do
      TradingMode.switch_to!("exit_only", changed_by: "dashboard")
      expect(circuit_breaker.triggered?).to be false
    end

    it "returns false when mode is blocked" do
      TradingMode.switch_to!("blocked", changed_by: "circuit_breaker")
      expect(circuit_breaker.triggered?).to be false
    end
  end

  describe "#trigger_reason" do
    before do
      create(:trading_mode, mode: "enabled")
    end

    it "returns nil when mode is enabled" do
      expect(circuit_breaker.trigger_reason).to be_nil
    end

    it "returns reason when mode is exit_only" do
      TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker", reason: "Test reason")
      expect(circuit_breaker.trigger_reason).to eq("Test reason")
    end

    it "returns reason when mode is blocked" do
      TradingMode.switch_to!("blocked", changed_by: "dashboard", reason: "Manual halt")
      expect(circuit_breaker.trigger_reason).to eq("Manual halt")
    end
  end

  describe "#status" do
    before do
      create(:trading_mode, mode: "enabled")
    end

    it "returns current state" do
      circuit_breaker.record_loss(100)

      status = circuit_breaker.status

      expect(status[:trading_allowed]).to be true
      expect(status[:daily_loss]).to eq(100)
      expect(status[:consecutive_losses]).to eq(1)
      expect(status[:triggered]).to be false
      expect(status[:trading_mode]).to eq("enabled")
    end

    it "reflects triggered state" do
      circuit_breaker.trigger!("test")

      status = circuit_breaker.status

      expect(status[:trading_allowed]).to be false
      expect(status[:triggered]).to be true
      expect(status[:trading_mode]).to eq("exit_only")
      expect(status[:trading_mode_changed_by]).to eq("circuit_breaker")
    end
  end

  describe "daily reset" do
    it "resets daily loss at midnight" do
      circuit_breaker.record_loss(100)

      travel_to(Date.tomorrow.beginning_of_day + 1.minute) do
        # Daily loss should reset with new day
        expect(circuit_breaker.daily_loss).to eq(0)
      end
    end
  end
end
