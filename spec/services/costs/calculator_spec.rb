# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::Calculator do
  subject(:calculator) { described_class.new }

  describe "#summary" do
    it "returns cost breakdown for a period" do
      result = calculator.summary(period: :today)

      expect(result).to include(
        :period,
        :period_start,
        :trading_fees,
        :llm_costs,
        :server_cost,
        :total_costs,
        :breakdown
      )
    end

    it "calculates total costs from all sources" do
      result = calculator.summary(period: :today)

      expected_total = (
        result[:trading_fees][:total] +
        result[:llm_costs][:total] +
        result[:server_cost][:prorated]
      ).round(2)

      expect(result[:total_costs]).to eq(expected_total)
    end

    context "with valid periods" do
      %i[today week month all].each do |period|
        it "accepts #{period} as a valid period" do
          expect { calculator.summary(period: period) }.not_to raise_error
        end
      end
    end

    context "with invalid period" do
      it "raises ArgumentError for invalid period" do
        expect { calculator.summary(period: :invalid) }
          .to raise_error(ArgumentError, /Invalid period/)
      end
    end

    context "with data" do
      before do
        macro = create(:macro_strategy)
        create(:trading_decision, macro_strategy: macro)
        create(:position, :closed, entry_price: 100_000, current_price: 102_000, size: 0.1, closed_at: 1.hour.ago)
      end

      it "includes trading fees from positions" do
        result = calculator.summary(period: :today)

        expect(result[:trading_fees][:total]).to be > 0
      end

      it "includes LLM costs from decisions" do
        result = calculator.summary(period: :today)

        expect(result[:llm_costs][:total]).to be >= 0
      end

      it "includes server costs" do
        result = calculator.summary(period: :today)

        expect(result[:server_cost][:daily_rate]).to be > 0
        expect(result[:server_cost][:prorated]).to be >= 0
      end
    end
  end

  describe "#net_pnl" do
    context "with no positions" do
      it "returns zero P&L" do
        result = calculator.net_pnl(period: :today)

        expect(result[:gross_realized_pnl]).to eq(0.0)
        expect(result[:net_realized_pnl]).to eq(0.0)
      end
    end

    context "with closed positions" do
      before do
        create(:position, :closed,
          entry_price: 100_000,
          current_price: 105_000,
          size: 0.1,
          realized_pnl: 500,
          closed_at: 1.hour.ago
        )
      end

      it "calculates gross realized P&L" do
        result = calculator.net_pnl(period: :today)

        expect(result[:gross_realized_pnl]).to eq(500.0)
      end

      it "deducts trading fees from gross P&L" do
        result = calculator.net_pnl(period: :today)

        expect(result[:net_realized_pnl]).to be < result[:gross_realized_pnl]
        expect(result[:trading_fees]).to be > 0
      end

      it "includes formula: net = gross - fees" do
        result = calculator.net_pnl(period: :today)

        expect(result[:net_realized_pnl]).to eq(
          (result[:gross_realized_pnl] - result[:trading_fees]).round(2)
        )
      end
    end

    context "with open positions" do
      before do
        create(:position, :profitable,
          entry_price: 100_000,
          current_price: 105_000,
          size: 0.1,
          unrealized_pnl: 500
        )
      end

      it "includes unrealized P&L" do
        result = calculator.net_pnl(period: :today)

        expect(result[:gross_unrealized_pnl]).to eq(500.0)
      end

      it "does not deduct fees from unrealized P&L" do
        # Fees for open positions are not realized yet
        result = calculator.net_pnl(period: :today)

        expect(result[:net_unrealized_pnl]).to eq(result[:gross_unrealized_pnl])
      end

      it "calculates total net P&L" do
        result = calculator.net_pnl(period: :today)

        expected_total = result[:net_realized_pnl] + result[:net_unrealized_pnl]
        expect(result[:net_total_pnl]).to eq(expected_total.round(2))
      end
    end
  end

  describe "server cost calculation" do
    context "for different periods" do
      it "calculates daily rate from monthly cost" do
        result = calculator.summary(period: :today)

        monthly = Settings.costs.server.monthly_cost.to_f
        expected_daily = (monthly / 30.0).round(4)

        expect(result[:server_cost][:daily_rate]).to eq(expected_daily)
      end

      it "prorates based on period days" do
        result_today = calculator.summary(period: :today)
        result_week = calculator.summary(period: :week)

        # Week should have more prorated cost than today
        expect(result_week[:server_cost][:days]).to be >= result_today[:server_cost][:days]
      end
    end
  end
end
