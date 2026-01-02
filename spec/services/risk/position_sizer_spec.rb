# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::PositionSizer do
  let(:position_sizer) { described_class.new }
  let(:account_manager) { instance_double(Execution::AccountManager) }

  before do
    allow(Execution::AccountManager).to receive(:new).and_return(account_manager)
  end

  describe "#calculate" do
    context "with valid inputs" do
      before do
        allow(account_manager).to receive(:fetch_account_state).and_return({ account_value: 10_000 })
      end

      it "calculates position size based on risk for long position" do
        # Account: $10,000, Max risk: 1%, Entry: $100,000, SL: $95,000
        # Risk per unit = $5,000, Max risk = $100
        # Position size = 100 / 5000 = 0.02 BTC
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 95_000,
          direction: "long"
        )

        expect(result[:size]).to eq(0.02)
        expect(result[:risk_amount]).to eq(100)
      end

      it "calculates position size for short position" do
        # Account: $10,000, Max risk: 1%, Entry: $100,000, SL: $105,000
        # Risk per unit = $5,000, Max risk = $100
        # Position size = 100 / 5000 = 0.02 BTC
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 105_000,
          direction: "short"
        )

        expect(result[:size]).to eq(0.02)
        expect(result[:risk_amount]).to eq(100)
      end

      it "caps size at max_position_size" do
        # With 2% SL distance and 1% risk, calculated size might exceed max
        # Let's say entry: 100k, SL: 99k (1% risk), max_risk_pct: 1%
        # Risk per unit = $1,000, Max risk = $100
        # Position size = 100 / 1000 = 0.1 BTC
        # But max_position_size is 0.05, so cap at 0.05
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 99_000,
          direction: "long"
        )

        expect(result[:size]).to eq(0.05) # Capped at max_position_size
        expect(result[:capped]).to be true
      end

      it "uses custom max_risk_pct when provided" do
        # Account: $10,000, Max risk: 2%, Entry: $100,000, SL: $95,000
        # Risk per unit = $5,000, Max risk = $200
        # Position size = 200 / 5000 = 0.04 BTC
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 95_000,
          direction: "long",
          max_risk_pct: 0.02
        )

        expect(result[:size]).to eq(0.04)
        expect(result[:risk_amount]).to eq(200)
      end

      it "uses custom account_value when provided" do
        # Account: $5,000 (custom), Max risk: 1%, Entry: $100,000, SL: $95,000
        # Risk per unit = $5,000, Max risk = $50
        # Position size = 50 / 5000 = 0.01 BTC
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 95_000,
          direction: "long",
          account_value: 5_000
        )

        expect(result[:size]).to eq(0.01)
        expect(result[:risk_amount]).to eq(50)
      end
    end

    context "with edge cases" do
      before do
        allow(account_manager).to receive(:fetch_account_state).and_return({ account_value: 10_000 })
      end

      it "returns nil when stop_loss is nil" do
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: nil,
          direction: "long"
        )

        expect(result).to be_nil
      end

      it "returns nil when stop_loss equals entry_price" do
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 100_000,
          direction: "long"
        )

        expect(result).to be_nil
      end
    end

    context "when account_value is zero" do
      before do
        allow(account_manager).to receive(:fetch_account_state).and_return({ account_value: 0 })
      end

      it "returns nil" do
        result = position_sizer.calculate(
          entry_price: 100_000,
          stop_loss: 95_000,
          direction: "long"
        )

        expect(result).to be_nil
      end
    end
  end

  describe "#optimal_size_for_decision" do
    let(:decision) do
      build(:trading_decision,
        direction: "long",
        parsed_decision: {
          "stop_loss" => 95_000,
          "take_profit" => 110_000
        }
      )
    end

    before do
      allow(account_manager).to receive(:fetch_account_state).and_return({ account_value: 10_000 })
    end

    it "calculates optimal size from decision" do
      result = position_sizer.optimal_size_for_decision(decision, entry_price: 100_000)

      expect(result[:size]).to eq(0.02)
    end

    it "returns nil when decision has no stop_loss" do
      decision_no_sl = build(:trading_decision, parsed_decision: {})

      result = position_sizer.optimal_size_for_decision(decision_no_sl, entry_price: 100_000)

      expect(result).to be_nil
    end
  end
end
