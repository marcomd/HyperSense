# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::RiskManager do
  let(:risk_manager) { described_class.new }
  let(:account_manager) { instance_double(Execution::AccountManager) }
  let(:position_manager) { instance_double(Execution::PositionManager) }

  before do
    allow(Execution::AccountManager).to receive(:new).and_return(account_manager)
    allow(Execution::PositionManager).to receive(:new).and_return(position_manager)
    allow(position_manager).to receive(:open_positions_count).and_return(0)
    allow(account_manager).to receive(:can_trade?).and_return(true)
  end

  describe "#validate" do
    let(:decision) do
      build(:trading_decision,
        operation: "open",
        direction: "long",
        symbol: "BTC",
        confidence: 0.75,
        parsed_decision: {
          "leverage" => 5,
          "target_position" => 0.03,
          "stop_loss" => 95_000,
          "take_profit" => 110_000
        }
      )
    end

    context "with valid decision" do
      before do
        allow(position_manager).to receive(:has_open_position?).with("BTC").and_return(false)
        allow(account_manager).to receive(:margin_for_position).and_return(1000)
        allow(account_manager).to receive(:fetch_account_state).and_return({ account_value: 10_000 })
      end

      it "returns approved result" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be true
        expect(result.rejection_reason).to be_nil
      end
    end

    context "when confidence is below threshold" do
      let(:decision) { build(:trading_decision, confidence: 0.5) }

      it "rejects with low confidence reason" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("Confidence")
      end
    end

    context "when max open positions reached" do
      before do
        allow(position_manager).to receive(:open_positions_count).and_return(5)
      end

      it "rejects when at max positions" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("max open positions")
      end
    end

    context "when leverage exceeds maximum" do
      let(:decision) do
        build(:trading_decision,
          operation: "open",
          confidence: 0.75,
          parsed_decision: { "leverage" => 15 }  # max is 10
        )
      end

      it "rejects with leverage exceeded reason" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("Leverage")
      end
    end

    context "when duplicate position exists" do
      before do
        allow(position_manager).to receive(:has_open_position?).with("BTC").and_return(true)
      end

      it "rejects open operation with existing position" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("existing position")
      end
    end

    context "when insufficient margin" do
      before do
        allow(position_manager).to receive(:has_open_position?).with("BTC").and_return(false)
        allow(account_manager).to receive(:margin_for_position).and_return(1000)
        allow(account_manager).to receive(:can_trade?).and_return(false)
      end

      it "rejects with insufficient margin reason" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("margin")
      end
    end

    context "when hold operation" do
      let(:decision) { build(:trading_decision, operation: "hold") }

      it "rejects hold operations" do
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("hold")
      end
    end

    context "for close operations" do
      let(:decision) do
        build(:trading_decision,
          operation: "close",
          symbol: "BTC",
          confidence: 0.75
        )
      end

      it "approves when position exists" do
        allow(position_manager).to receive(:has_open_position?).with("BTC").and_return(true)
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be true
      end

      it "rejects when no position exists" do
        allow(position_manager).to receive(:has_open_position?).with("BTC").and_return(false)
        result = risk_manager.validate(decision, entry_price: 100_000)
        expect(result.approved?).to be false
        expect(result.rejection_reason).to include("No open position")
      end
    end
  end

  describe "#validate_risk_reward" do
    context "when enforce_risk_reward_ratio is true" do
      before do
        allow(Settings.risk).to receive(:enforce_risk_reward_ratio).and_return(true)
        allow(Settings.risk).to receive(:min_risk_reward_ratio).and_return(2.0)
      end

      it "approves when R/R ratio meets minimum" do
        # Entry: 100k, SL: 95k (risk: 5k), TP: 115k (reward: 15k) => R/R = 3.0
        result = risk_manager.validate_risk_reward(
          entry_price: 100_000,
          stop_loss: 95_000,
          take_profit: 115_000,
          direction: "long"
        )
        expect(result[:valid]).to be true
      end

      it "rejects when R/R ratio below minimum" do
        # Entry: 100k, SL: 95k (risk: 5k), TP: 105k (reward: 5k) => R/R = 1.0
        result = risk_manager.validate_risk_reward(
          entry_price: 100_000,
          stop_loss: 95_000,
          take_profit: 105_000,
          direction: "long"
        )
        expect(result[:valid]).to be false
        expect(result[:reason]).to include("risk/reward")
      end

      it "handles short positions correctly" do
        # Entry: 100k, SL: 105k (risk: 5k), TP: 85k (reward: 15k) => R/R = 3.0
        result = risk_manager.validate_risk_reward(
          entry_price: 100_000,
          stop_loss: 105_000,
          take_profit: 85_000,
          direction: "short"
        )
        expect(result[:valid]).to be true
      end
    end

    context "when enforce_risk_reward_ratio is false" do
      before do
        allow(Settings.risk).to receive(:enforce_risk_reward_ratio).and_return(false)
      end

      it "approves even with poor R/R ratio but logs warning" do
        expect(Rails.logger).to receive(:warn).with(/risk\/reward/)

        result = risk_manager.validate_risk_reward(
          entry_price: 100_000,
          stop_loss: 95_000,
          take_profit: 102_000,
          direction: "long"
        )
        expect(result[:valid]).to be true
      end
    end

    context "when stop_loss or take_profit is nil" do
      it "approves when stop_loss is nil" do
        result = risk_manager.validate_risk_reward(
          entry_price: 100_000,
          stop_loss: nil,
          take_profit: 110_000,
          direction: "long"
        )
        expect(result[:valid]).to be true
      end
    end
  end

  describe "#calculate_risk_amount" do
    it "calculates risk amount for long position" do
      # Size: 0.1 BTC, Entry: 100k, SL: 95k => Risk = 0.1 * 5000 = 500
      risk = risk_manager.calculate_risk_amount(
        size: 0.1,
        entry_price: 100_000,
        stop_loss: 95_000,
        direction: "long"
      )
      expect(risk).to eq(500)
    end

    it "calculates risk amount for short position" do
      # Size: 0.1 BTC, Entry: 100k, SL: 105k => Risk = 0.1 * 5000 = 500
      risk = risk_manager.calculate_risk_amount(
        size: 0.1,
        entry_price: 100_000,
        stop_loss: 105_000,
        direction: "short"
      )
      expect(risk).to eq(500)
    end

    it "returns nil when stop_loss is nil" do
      risk = risk_manager.calculate_risk_amount(
        size: 0.1,
        entry_price: 100_000,
        stop_loss: nil,
        direction: "long"
      )
      expect(risk).to be_nil
    end
  end

  describe Risk::RiskManager::ValidationResult do
    describe "#approved?" do
      it "returns true when valid is true" do
        result = described_class.new(valid: true)
        expect(result.approved?).to be true
      end

      it "returns false when valid is false" do
        result = described_class.new(valid: false, reason: "test")
        expect(result.approved?).to be false
      end
    end
  end
end
