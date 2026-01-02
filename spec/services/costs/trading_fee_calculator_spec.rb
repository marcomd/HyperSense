# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::TradingFeeCalculator do
  subject(:calculator) { described_class.new }

  describe "#for_position" do
    context "with an open position" do
      let(:position) do
        create(:position, entry_price: 100_000, size: 0.1, current_price: 100_000)
      end

      it "calculates entry fee based on notional value" do
        # Notional = 100,000 * 0.1 = 10,000
        # Entry fee = 10,000 * 0.00045 = 4.5
        result = calculator.for_position(position)

        expect(result[:entry_fee]).to be_within(0.001).of(4.5)
        expect(result[:estimated]).to be true
      end

      it "estimates exit fee for open positions" do
        result = calculator.for_position(position)

        # Exit estimated at current_price
        expect(result[:exit_fee]).to be_within(0.001).of(4.5)
        expect(result[:total_fee]).to be_within(0.001).of(9.0)
      end

      it "includes fee rate in result" do
        result = calculator.for_position(position)

        expect(result[:fee_rate]).to eq(Settings.costs.trading.taker_fee_pct)
      end
    end

    context "with a closed position" do
      let(:position) do
        create(:position, :closed,
          entry_price: 100_000,
          current_price: 110_000,
          size: 0.1,
          realized_pnl: 1000
        )
      end

      it "calculates actual exit fee using current_price" do
        # Entry notional = 100,000 * 0.1 = 10,000
        # Exit notional = 110,000 * 0.1 = 11,000
        # Entry fee = 10,000 * 0.00045 = 4.5
        # Exit fee = 11,000 * 0.00045 = 4.95
        result = calculator.for_position(position)

        expect(result[:entry_fee]).to be_within(0.001).of(4.5)
        expect(result[:exit_fee]).to be_within(0.001).of(4.95)
        expect(result[:total_fee]).to be_within(0.001).of(9.45)
        expect(result[:estimated]).to be false
      end
    end

    context "with different position sizes" do
      it "scales fees linearly with notional value" do
        small_position = create(:position, entry_price: 100_000, size: 0.01)
        large_position = create(:position, entry_price: 100_000, size: 1.0)

        small_fees = calculator.for_position(small_position)
        large_fees = calculator.for_position(large_position)

        # 100x size difference = 100x fee difference
        expect(large_fees[:entry_fee]).to be_within(0.01).of(small_fees[:entry_fee] * 100)
      end
    end
  end

  describe "#total_fees" do
    context "with no positions" do
      it "returns zero fees" do
        result = calculator.total_fees(since: nil)

        expect(result[:total]).to eq(0.0)
        expect(result[:positions_counted]).to eq(0)
      end
    end

    context "with closed positions" do
      before do
        # Create closed positions with various values
        create(:position, :closed, entry_price: 100_000, current_price: 105_000, size: 0.1, closed_at: 1.day.ago)
        create(:position, :closed, entry_price: 50_000, current_price: 48_000, size: 0.2, closed_at: 2.days.ago)
      end

      it "calculates total fees for all closed positions" do
        result = calculator.total_fees(since: nil)

        expect(result[:entry_fees]).to be > 0
        expect(result[:exit_fees]).to be > 0
        expect(result[:total]).to eq(result[:entry_fees] + result[:exit_fees] + result[:open_position_entry_fees])
      end

      it "filters by since date" do
        result_all = calculator.total_fees(since: nil)
        result_recent = calculator.total_fees(since: 1.day.ago.beginning_of_day)

        # Only 1 position in last day
        expect(result_recent[:positions_counted]).to eq(1)
        expect(result_all[:positions_counted]).to eq(2)
      end
    end

    context "with open positions" do
      before do
        create(:position, entry_price: 100_000, size: 0.1)
      end

      it "includes open position entry fees" do
        result = calculator.total_fees(since: nil)

        # Entry fee for open position = 10,000 * 0.00045 = 4.5
        expect(result[:open_position_entry_fees]).to be_within(0.001).of(4.5)
      end
    end
  end

  describe "#estimate" do
    it "estimates fees for a notional value" do
      # $10,000 notional, taker fee = 0.045%
      result = calculator.estimate(notional_value: 10_000, round_trip: true)

      expect(result[:entry_fee]).to be_within(0.001).of(4.5)
      expect(result[:exit_fee]).to be_within(0.001).of(4.5)
      expect(result[:total_fee]).to be_within(0.001).of(9.0)
    end

    it "can estimate entry-only fees" do
      result = calculator.estimate(notional_value: 10_000, round_trip: false)

      expect(result[:exit_fee]).to eq(0.0)
      expect(result[:total_fee]).to be_within(0.001).of(4.5)
    end

    it "returns fee rate used" do
      result = calculator.estimate(notional_value: 10_000)

      expect(result[:fee_rate]).to eq(Settings.costs.trading.taker_fee_pct)
    end
  end
end
