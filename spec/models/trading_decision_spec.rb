# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingDecision do
  describe "associations" do
    it "belongs to macro_strategy optionally" do
      decision = build(:trading_decision, :without_macro_strategy)
      expect(decision).to be_valid
    end

    it "can have a macro_strategy" do
      strategy = create(:macro_strategy)
      decision = build(:trading_decision, macro_strategy: strategy)
      expect(decision.macro_strategy).to eq(strategy)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      decision = build(:trading_decision)
      expect(decision).to be_valid
    end

    it "requires symbol" do
      decision = build(:trading_decision, symbol: nil)
      expect(decision).not_to be_valid
      expect(decision.errors[:symbol]).to include("can't be blank")
    end

    it "requires status" do
      decision = build(:trading_decision, status: nil)
      expect(decision).not_to be_valid
      expect(decision.errors[:status]).to include("can't be blank")
    end

    it "requires status to be one of pending, approved, rejected, executed, failed" do
      %w[pending approved rejected executed failed].each do |valid_status|
        decision = build(:trading_decision, status: valid_status)
        expect(decision).to be_valid
      end

      decision = build(:trading_decision, status: "invalid")
      expect(decision).not_to be_valid
      expect(decision.errors[:status]).to include("is not included in the list")
    end

    it "requires operation to be one of open, close, hold if present" do
      %w[open close hold].each do |valid_op|
        decision = build(:trading_decision, operation: valid_op)
        expect(decision).to be_valid
      end

      decision = build(:trading_decision, operation: "invalid")
      expect(decision).not_to be_valid
    end

    it "requires direction to be one of long, short if present" do
      %w[long short].each do |valid_dir|
        decision = build(:trading_decision, direction: valid_dir)
        expect(decision).to be_valid
      end

      decision = build(:trading_decision, direction: "invalid")
      expect(decision).not_to be_valid
    end

    it "requires confidence between 0 and 1 if present" do
      decision = build(:trading_decision, confidence: -0.1)
      expect(decision).not_to be_valid

      decision = build(:trading_decision, confidence: 1.1)
      expect(decision).not_to be_valid

      decision = build(:trading_decision, confidence: 0.78)
      expect(decision).to be_valid
    end

    it "requires next_cycle_interval between 1 and 30 if present" do
      decision = build(:trading_decision, next_cycle_interval: 0)
      expect(decision).not_to be_valid

      decision = build(:trading_decision, next_cycle_interval: 31)
      expect(decision).not_to be_valid

      decision = build(:trading_decision, next_cycle_interval: 12)
      expect(decision).to be_valid
    end
  end

  describe "volatility_level enum" do
    it "has valid volatility levels" do
      %i[very_high high medium low].each do |level|
        decision = build(:trading_decision, volatility_level: level)
        expect(decision).to be_valid
      end
    end

    it "defaults to medium" do
      decision = TradingDecision.new(symbol: "BTC", status: "pending")
      expect(decision.volatility_level).to eq("medium")
    end

    it "provides scoped query methods with volatility_ prefix" do
      create(:trading_decision, volatility_level: :very_high)
      create(:trading_decision, volatility_level: :medium)

      expect(TradingDecision.volatility_very_high.count).to eq(1)
      expect(TradingDecision.volatility_medium.count).to eq(1)
    end

    it "provides predicate methods with volatility_ prefix" do
      decision = build(:trading_decision, volatility_level: :high)
      expect(decision.volatility_high?).to be true
      expect(decision.volatility_low?).to be false
    end
  end

  describe "scopes" do
    describe ".for_symbol" do
      it "filters by symbol" do
        btc_decision = create(:trading_decision, symbol: "BTC")
        _eth_decision = create(:trading_decision, symbol: "ETH")

        expect(TradingDecision.for_symbol("BTC")).to contain_exactly(btc_decision)
      end
    end

    describe ".pending" do
      it "returns only pending decisions" do
        pending_decision = create(:trading_decision, status: "pending")
        _approved_decision = create(:trading_decision, :approved)

        expect(TradingDecision.pending).to contain_exactly(pending_decision)
      end
    end

    describe ".approved" do
      it "returns only approved decisions" do
        approved_decision = create(:trading_decision, :approved)
        _pending_decision = create(:trading_decision, status: "pending")

        expect(TradingDecision.approved).to contain_exactly(approved_decision)
      end
    end

    describe ".actionable" do
      it "returns decisions with open or close operations" do
        open_decision = create(:trading_decision, operation: "open")
        close_decision = create(:trading_decision, operation: "close")
        _hold_decision = create(:trading_decision, :hold)

        expect(TradingDecision.actionable).to contain_exactly(open_decision, close_decision)
      end
    end

    describe ".holds" do
      it "returns only hold decisions" do
        hold_decision = create(:trading_decision, :hold)
        _open_decision = create(:trading_decision, operation: "open")

        expect(TradingDecision.holds).to contain_exactly(hold_decision)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        older = create(:trading_decision, created_at: 2.hours.ago)
        newer = create(:trading_decision, created_at: 1.hour.ago)

        expect(TradingDecision.recent.first).to eq(newer)
        expect(TradingDecision.recent.last).to eq(older)
      end
    end
  end

  describe "state transitions" do
    describe "#approve!" do
      it "sets status to approved" do
        decision = create(:trading_decision, status: "pending")
        decision.approve!
        expect(decision.reload.status).to eq("approved")
      end
    end

    describe "#reject!" do
      it "sets status to rejected with reason" do
        decision = create(:trading_decision, status: "pending")
        decision.reject!("Confidence too low")
        decision.reload
        expect(decision.status).to eq("rejected")
        expect(decision.rejection_reason).to eq("Confidence too low")
      end
    end

    describe "#mark_executed!" do
      it "sets status to executed and executed flag to true" do
        decision = create(:trading_decision, :approved)
        decision.mark_executed!
        decision.reload
        expect(decision.status).to eq("executed")
        expect(decision.executed).to be true
      end
    end

    describe "#mark_failed!" do
      it "sets status to failed with reason" do
        decision = create(:trading_decision, :approved)
        decision.mark_failed!("API error")
        decision.reload
        expect(decision.status).to eq("failed")
        expect(decision.rejection_reason).to eq("API error")
      end
    end
  end

  describe "helper methods" do
    describe "#approved?" do
      it "returns true when status is approved" do
        decision = build(:trading_decision, :approved)
        expect(decision.approved?).to be true
      end

      it "returns false when status is not approved" do
        decision = build(:trading_decision, status: "pending")
        expect(decision.approved?).to be false
      end
    end

    describe "#actionable?" do
      it "returns true for open operations" do
        decision = build(:trading_decision, operation: "open")
        expect(decision.actionable?).to be true
      end

      it "returns true for close operations" do
        decision = build(:trading_decision, operation: "close")
        expect(decision.actionable?).to be true
      end

      it "returns false for hold operations" do
        decision = build(:trading_decision, :hold)
        expect(decision.actionable?).to be false
      end
    end

    describe "#hold?" do
      it "returns true when operation is hold" do
        decision = build(:trading_decision, :hold)
        expect(decision.hold?).to be true
      end

      it "returns false when operation is not hold" do
        decision = build(:trading_decision, operation: "open")
        expect(decision.hold?).to be false
      end
    end

    describe "parsed_decision accessors" do
      let(:decision) do
        build(:trading_decision, parsed_decision: {
          "leverage" => 5,
          "target_position" => 0.02,
          "stop_loss" => 95_000,
          "take_profit" => 105_000,
          "reasoning" => "Strong setup"
        })
      end

      it "#leverage returns the leverage from parsed_decision" do
        expect(decision.leverage).to eq(5)
      end

      it "#target_position returns the target_position from parsed_decision" do
        expect(decision.target_position).to eq(0.02)
      end

      it "#stop_loss returns the stop_loss from parsed_decision" do
        expect(decision.stop_loss).to eq(95_000)
      end

      it "#take_profit returns the take_profit from parsed_decision" do
        expect(decision.take_profit).to eq(105_000)
      end

      it "#reasoning returns the reasoning from parsed_decision" do
        expect(decision.reasoning).to eq("Strong setup")
      end
    end

    describe "parsed_decision accessors with string values (LLM JSON)" do
      # LLM responses often return numeric values as strings in JSON
      let(:decision) do
        build(:trading_decision, parsed_decision: {
          "leverage" => "5",
          "target_position" => "0.02",
          "stop_loss" => "95000",
          "take_profit" => "105000.50",
          "reasoning" => "Strong setup"
        })
      end

      it "#leverage converts string to integer" do
        expect(decision.leverage).to eq(5)
        expect(decision.leverage).to be_a(Integer)
      end

      it "#target_position converts string to float" do
        expect(decision.target_position).to eq(0.02)
        expect(decision.target_position).to be_a(Float)
      end

      it "#stop_loss converts string to float" do
        expect(decision.stop_loss).to eq(95_000.0)
        expect(decision.stop_loss).to be_a(Float)
      end

      it "#take_profit converts string to float" do
        expect(decision.take_profit).to eq(105_000.50)
        expect(decision.take_profit).to be_a(Float)
      end

      it "returns nil for missing values without raising errors" do
        empty_decision = build(:trading_decision, parsed_decision: {})
        expect(empty_decision.leverage).to be_nil
        expect(empty_decision.target_position).to be_nil
        expect(empty_decision.stop_loss).to be_nil
        expect(empty_decision.take_profit).to be_nil
      end
    end
  end
end
