# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::CircuitBreaker do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:circuit_breaker) { described_class.new }

  before do
    # Use memory store for tests
    allow(Rails).to receive(:cache).and_return(memory_store)
  end

  describe "#trading_allowed?" do
    context "when no losses" do
      it "returns true" do
        expect(circuit_breaker.trading_allowed?).to be true
      end
    end

    context "when daily loss exceeds max" do
      before do
        # Simulate 6% daily loss (max is 5%)
        circuit_breaker.record_loss(600) # $600 loss on $10,000 account = 6%
        allow(circuit_breaker).to receive(:fetch_account_value).and_return(10_000)
      end

      it "returns false" do
        expect(circuit_breaker.trading_allowed?).to be false
      end
    end

    context "when consecutive losses exceed max" do
      before do
        # Record 4 consecutive losses (max is 3)
        4.times { circuit_breaker.record_loss(50) }
      end

      it "returns false" do
        expect(circuit_breaker.trading_allowed?).to be false
      end
    end

    context "during cooldown period" do
      before do
        circuit_breaker.trigger!("test")
      end

      it "returns false" do
        expect(circuit_breaker.trading_allowed?).to be false
      end
    end

    context "after cooldown expires" do
      before do
        circuit_breaker.trigger!("test")
        # Advance time past cooldown
        travel_to(25.hours.from_now)
      end

      it "returns true" do
        expect(circuit_breaker.trading_allowed?).to be true
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
    it "sets triggered state" do
      circuit_breaker.trigger!("max_daily_loss")
      expect(circuit_breaker.triggered?).to be true
    end

    it "records trigger reason" do
      circuit_breaker.trigger!("consecutive_losses")
      expect(circuit_breaker.trigger_reason).to eq("consecutive_losses")
    end

    it "sets cooldown expiry" do
      freeze_time do
        circuit_breaker.trigger!("test")
        expect(circuit_breaker.cooldown_until).to eq(24.hours.from_now)
      end
    end
  end

  describe "#reset!" do
    before do
      circuit_breaker.record_loss(100)
      circuit_breaker.record_loss(50)
      circuit_breaker.trigger!("test")
    end

    it "clears all state" do
      circuit_breaker.reset!

      expect(circuit_breaker.daily_loss).to eq(0)
      expect(circuit_breaker.consecutive_losses).to eq(0)
      expect(circuit_breaker.triggered?).to be false
    end
  end

  describe "#check_and_update!" do
    before do
      allow(circuit_breaker).to receive(:fetch_account_value).and_return(10_000)
    end

    context "when daily loss exceeds threshold" do
      before do
        circuit_breaker.record_loss(600) # 6% of $10,000
      end

      it "triggers circuit breaker" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be true
        expect(circuit_breaker.trigger_reason).to eq("max_daily_loss")
      end
    end

    context "when consecutive losses exceed threshold" do
      before do
        4.times { circuit_breaker.record_loss(50) }
      end

      it "triggers circuit breaker" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be true
        expect(circuit_breaker.trigger_reason).to eq("consecutive_losses")
      end
    end

    context "when within limits" do
      before do
        circuit_breaker.record_loss(100) # 1% loss, 1 consecutive
      end

      it "does not trigger" do
        circuit_breaker.check_and_update!
        expect(circuit_breaker.triggered?).to be false
      end
    end
  end

  describe "#status" do
    it "returns current state" do
      circuit_breaker.record_loss(100)

      status = circuit_breaker.status

      expect(status[:trading_allowed]).to be true
      expect(status[:daily_loss]).to eq(100)
      expect(status[:consecutive_losses]).to eq(1)
      expect(status[:triggered]).to be false
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
