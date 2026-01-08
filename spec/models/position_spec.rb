# frozen_string_literal: true

require "rails_helper"

RSpec.describe Position do
  describe "associations" do
    it "has many orders" do
      position = create(:position)
      order = create(:order, position: position)
      expect(position.orders).to include(order)
    end

    it "has many execution_logs as loggable" do
      position = create(:position)
      log = create(:execution_log, loggable: position)
      expect(position.execution_logs).to include(log)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      position = build(:position)
      expect(position).to be_valid
    end

    it "requires symbol" do
      position = build(:position, symbol: nil)
      expect(position).not_to be_valid
      expect(position.errors[:symbol]).to include("can't be blank")
    end

    it "requires direction" do
      position = build(:position, direction: nil)
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to include("can't be blank")
    end

    it "requires direction to be long or short" do
      %w[long short].each do |valid_direction|
        position = build(:position, direction: valid_direction)
        expect(position).to be_valid
      end

      position = build(:position, direction: "invalid")
      expect(position).not_to be_valid
      expect(position.errors[:direction]).to include("is not included in the list")
    end

    it "requires status to be open, closing, or closed" do
      %w[open closing closed].each do |valid_status|
        position = build(:position, status: valid_status)
        expect(position).to be_valid
      end

      position = build(:position, status: "invalid")
      expect(position).not_to be_valid
      expect(position.errors[:status]).to include("is not included in the list")
    end

    it "requires size to be greater than 0" do
      position = build(:position, size: 0)
      expect(position).not_to be_valid

      position = build(:position, size: -1)
      expect(position).not_to be_valid

      position = build(:position, size: 0.001)
      expect(position).to be_valid
    end

    it "requires entry_price to be greater than 0" do
      position = build(:position, entry_price: 0)
      expect(position).not_to be_valid

      position = build(:position, entry_price: 100_000)
      expect(position).to be_valid
    end

    it "requires leverage to be between 1 and 100" do
      position = build(:position, leverage: 0)
      expect(position).not_to be_valid

      position = build(:position, leverage: 101)
      expect(position).not_to be_valid

      position = build(:position, leverage: 10)
      expect(position).to be_valid
    end

    it "validates close_reason when present" do
      %w[sl_triggered tp_triggered manual signal liquidated].each do |valid_reason|
        position = build(:position, :closed, close_reason: valid_reason)
        expect(position).to be_valid
      end

      position = build(:position, :closed, close_reason: "invalid_reason")
      expect(position).not_to be_valid
      expect(position.errors[:close_reason]).to include("is not included in the list")
    end

    it "allows nil close_reason" do
      position = build(:position, close_reason: nil)
      expect(position).to be_valid
    end

    it "validates stop_loss_price is positive when present" do
      position = build(:position, stop_loss_price: -100)
      expect(position).not_to be_valid

      position = build(:position, stop_loss_price: 95_000)
      expect(position).to be_valid
    end

    it "validates take_profit_price is positive when present" do
      position = build(:position, take_profit_price: -100)
      expect(position).not_to be_valid

      position = build(:position, take_profit_price: 105_000)
      expect(position).to be_valid
    end

    it "validates risk_amount is non-negative when present" do
      position = build(:position, risk_amount: -100)
      expect(position).not_to be_valid

      position = build(:position, risk_amount: 0)
      expect(position).to be_valid

      position = build(:position, risk_amount: 500)
      expect(position).to be_valid
    end
  end

  describe "scopes" do
    describe ".open" do
      it "returns only open positions" do
        open_position = create(:position, status: "open")
        _closed_position = create(:position, :closed)

        expect(Position.open).to contain_exactly(open_position)
      end
    end

    describe ".closed" do
      it "returns only closed positions" do
        _open_position = create(:position, status: "open")
        closed_position = create(:position, :closed)

        expect(Position.closed).to contain_exactly(closed_position)
      end
    end

    describe ".for_symbol" do
      it "filters by symbol" do
        btc_position = create(:position, symbol: "BTC")
        _eth_position = create(:position, symbol: "ETH")

        expect(Position.for_symbol("BTC")).to contain_exactly(btc_position)
      end
    end

    describe ".long" do
      it "returns only long positions" do
        long_position = create(:position, direction: "long")
        _short_position = create(:position, :short)

        expect(Position.long).to contain_exactly(long_position)
      end
    end

    describe ".short" do
      it "returns only short positions" do
        _long_position = create(:position, direction: "long")
        short_position = create(:position, :short)

        expect(Position.short).to contain_exactly(short_position)
      end
    end

    describe ".recent" do
      it "orders by opened_at descending" do
        older = create(:position, opened_at: 2.hours.ago)
        newer = create(:position, opened_at: 1.hour.ago)

        expect(Position.recent.first).to eq(newer)
        expect(Position.recent.last).to eq(older)
      end
    end
  end

  describe "state transitions" do
    describe "#close!" do
      it "sets status to closed and records closed_at" do
        position = create(:position, status: "open", unrealized_pnl: 100)

        freeze_time do
          position.close!
          position.reload

          expect(position.status).to eq("closed")
          expect(position.closed_at).to eq(Time.current)
          expect(position.close_reason).to eq("manual")
          expect(position.realized_pnl).to eq(100)
        end
      end

      it "accepts custom close_reason and pnl" do
        position = create(:position, status: "open", unrealized_pnl: 100)

        position.close!(reason: "sl_triggered", pnl: -50)
        position.reload

        expect(position.close_reason).to eq("sl_triggered")
        expect(position.realized_pnl).to eq(-50)
      end

      it "uses unrealized_pnl when pnl not specified" do
        position = create(:position, status: "open", unrealized_pnl: 250)

        position.close!(reason: "tp_triggered")
        position.reload

        expect(position.realized_pnl).to eq(250)
      end
    end

    describe "#mark_closing!" do
      it "sets status to closing" do
        position = create(:position, status: "open")
        position.mark_closing!

        expect(position.reload.status).to eq("closing")
      end
    end
  end

  describe "helper methods" do
    describe "#open?" do
      it "returns true when status is open" do
        position = build(:position, status: "open")
        expect(position.open?).to be true
      end

      it "returns false when status is not open" do
        position = build(:position, :closed)
        expect(position.open?).to be false
      end
    end

    describe "#closed?" do
      it "returns true when status is closed" do
        position = build(:position, :closed)
        expect(position.closed?).to be true
      end

      it "returns false when status is not closed" do
        position = build(:position, status: "open")
        expect(position.closed?).to be false
      end
    end

    describe "#long?" do
      it "returns true when direction is long" do
        position = build(:position, direction: "long")
        expect(position.long?).to be true
      end

      it "returns false when direction is short" do
        position = build(:position, :short)
        expect(position.long?).to be false
      end
    end

    describe "#short?" do
      it "returns true when direction is short" do
        position = build(:position, :short)
        expect(position.short?).to be true
      end

      it "returns false when direction is long" do
        position = build(:position, direction: "long")
        expect(position.short?).to be false
      end
    end

    describe "#pnl_percent" do
      context "when long position" do
        it "calculates positive PnL when price increased" do
          position = build(:position, direction: "long", entry_price: 100_000, current_price: 110_000)
          expect(position.pnl_percent).to eq(10.0)
        end

        it "calculates negative PnL when price decreased" do
          position = build(:position, direction: "long", entry_price: 100_000, current_price: 90_000)
          expect(position.pnl_percent).to eq(-10.0)
        end
      end

      context "when short position" do
        it "calculates positive PnL when price decreased" do
          position = build(:position, :short, entry_price: 100_000, current_price: 90_000)
          expect(position.pnl_percent).to eq(10.0)
        end

        it "calculates negative PnL when price increased" do
          position = build(:position, :short, entry_price: 100_000, current_price: 110_000)
          expect(position.pnl_percent).to eq(-10.0)
        end
      end

      it "returns 0 when current_price is nil" do
        position = build(:position, current_price: nil)
        expect(position.pnl_percent).to eq(0)
      end
    end

    describe "#notional_value" do
      it "calculates size * entry_price" do
        position = build(:position, size: 0.5, entry_price: 100_000)
        expect(position.notional_value).to eq(50_000)
      end
    end

    describe "#update_current_price!" do
      it "updates current_price and unrealized_pnl" do
        position = create(:position, direction: "long", size: 0.1, entry_price: 100_000, current_price: 100_000)
        position.update_current_price!(105_000)
        position.reload

        expect(position.current_price).to eq(105_000)
        expect(position.unrealized_pnl).to eq(500) # 0.1 * (105000 - 100000)
      end

      it "calculates unrealized PnL correctly for short positions" do
        position = create(:position, :short, size: 0.1, entry_price: 100_000, current_price: 100_000)
        position.update_current_price!(95_000)
        position.reload

        expect(position.unrealized_pnl).to eq(500) # 0.1 * (100000 - 95000)
      end
    end
  end

  describe "risk management" do
    describe "#has_stop_loss?" do
      it "returns true when stop_loss_price is set" do
        position = build(:position, stop_loss_price: 95_000)
        expect(position.has_stop_loss?).to be true
      end

      it "returns false when stop_loss_price is nil" do
        position = build(:position, stop_loss_price: nil)
        expect(position.has_stop_loss?).to be false
      end
    end

    describe "#has_take_profit?" do
      it "returns true when take_profit_price is set" do
        position = build(:position, take_profit_price: 110_000)
        expect(position.has_take_profit?).to be true
      end

      it "returns false when take_profit_price is nil" do
        position = build(:position, take_profit_price: nil)
        expect(position.has_take_profit?).to be false
      end
    end

    describe "#stop_loss_triggered?" do
      context "for long positions" do
        it "returns true when price <= stop_loss" do
          position = build(:position, direction: "long", stop_loss_price: 95_000, current_price: 94_000)
          expect(position.stop_loss_triggered?).to be true
        end

        it "returns true when price == stop_loss" do
          position = build(:position, direction: "long", stop_loss_price: 95_000, current_price: 95_000)
          expect(position.stop_loss_triggered?).to be true
        end

        it "returns false when price > stop_loss" do
          position = build(:position, direction: "long", stop_loss_price: 95_000, current_price: 96_000)
          expect(position.stop_loss_triggered?).to be false
        end
      end

      context "for short positions" do
        it "returns true when price >= stop_loss" do
          position = build(:position, :short, stop_loss_price: 105_000, current_price: 106_000)
          expect(position.stop_loss_triggered?).to be true
        end

        it "returns false when price < stop_loss" do
          position = build(:position, :short, stop_loss_price: 105_000, current_price: 104_000)
          expect(position.stop_loss_triggered?).to be false
        end
      end

      it "returns false when stop_loss_price is nil" do
        position = build(:position, stop_loss_price: nil)
        expect(position.stop_loss_triggered?).to be false
      end

      it "accepts custom price parameter" do
        position = build(:position, direction: "long", stop_loss_price: 95_000, current_price: 100_000)
        expect(position.stop_loss_triggered?(94_000)).to be true
        expect(position.stop_loss_triggered?(96_000)).to be false
      end
    end

    describe "#take_profit_triggered?" do
      context "for long positions" do
        it "returns true when price >= take_profit" do
          position = build(:position, direction: "long", take_profit_price: 110_000, current_price: 111_000)
          expect(position.take_profit_triggered?).to be true
        end

        it "returns false when price < take_profit" do
          position = build(:position, direction: "long", take_profit_price: 110_000, current_price: 109_000)
          expect(position.take_profit_triggered?).to be false
        end
      end

      context "for short positions" do
        it "returns true when price <= take_profit" do
          position = build(:position, :short, take_profit_price: 90_000, current_price: 89_000)
          expect(position.take_profit_triggered?).to be true
        end

        it "returns false when price > take_profit" do
          position = build(:position, :short, take_profit_price: 90_000, current_price: 91_000)
          expect(position.take_profit_triggered?).to be false
        end
      end

      it "returns false when take_profit_price is nil" do
        position = build(:position, take_profit_price: nil)
        expect(position.take_profit_triggered?).to be false
      end
    end

    describe "#risk_reward_ratio" do
      it "calculates R/R ratio correctly for long position" do
        # Entry: 100k, SL: 95k (risk: 5k), TP: 115k (reward: 15k) => R/R = 3.0
        position = build(:position, direction: "long", entry_price: 100_000, stop_loss_price: 95_000, take_profit_price: 115_000)
        expect(position.risk_reward_ratio).to eq(3.0)
      end

      it "calculates R/R ratio correctly for short position" do
        # Entry: 100k, SL: 105k (risk: 5k), TP: 90k (reward: 10k) => R/R = 2.0
        position = build(:position, :short, entry_price: 100_000, stop_loss_price: 105_000, take_profit_price: 90_000)
        expect(position.risk_reward_ratio).to eq(2.0)
      end

      it "returns nil when stop_loss_price is missing" do
        position = build(:position, stop_loss_price: nil, take_profit_price: 110_000)
        expect(position.risk_reward_ratio).to be_nil
      end

      it "returns nil when take_profit_price is missing" do
        position = build(:position, stop_loss_price: 95_000, take_profit_price: nil)
        expect(position.risk_reward_ratio).to be_nil
      end
    end

    describe "#stop_loss_distance_pct" do
      it "calculates distance for long position" do
        # Current: 100k, SL: 95k => 5% buffer
        position = build(:position, direction: "long", current_price: 100_000, stop_loss_price: 95_000)
        expect(position.stop_loss_distance_pct).to eq(5.0)
      end

      it "calculates distance for short position" do
        # Current: 100k, SL: 105k => 5% buffer
        position = build(:position, :short, current_price: 100_000, stop_loss_price: 105_000)
        expect(position.stop_loss_distance_pct).to eq(5.0)
      end

      it "returns nil when stop_loss_price is nil" do
        position = build(:position, stop_loss_price: nil)
        expect(position.stop_loss_distance_pct).to be_nil
      end
    end

    describe "#take_profit_distance_pct" do
      it "calculates distance for long position" do
        # Current: 100k, TP: 110k => 10% to target
        position = build(:position, direction: "long", current_price: 100_000, take_profit_price: 110_000)
        expect(position.take_profit_distance_pct).to eq(10.0)
      end

      it "calculates distance for short position" do
        # Current: 100k, TP: 90k => 10% to target
        position = build(:position, :short, current_price: 100_000, take_profit_price: 90_000)
        expect(position.take_profit_distance_pct).to eq(10.0)
      end

      it "returns nil when take_profit_price is nil" do
        position = build(:position, take_profit_price: nil)
        expect(position.take_profit_distance_pct).to be_nil
      end
    end
  end

  describe "trading fees" do
    describe "#entry_fee" do
      it "calculates entry fee based on notional value" do
        # Notional = 100,000 * 0.1 = 10,000
        # Fee = 10,000 * 0.00045 = 4.5
        position = build(:position, entry_price: 100_000, size: 0.1)
        expect(position.entry_fee).to be_within(0.001).of(4.5)
      end
    end

    describe "#exit_fee" do
      it "estimates exit fee for open positions using current price" do
        position = build(:position, entry_price: 100_000, current_price: 105_000, size: 0.1)
        # Exit notional = 105,000 * 0.1 = 10,500
        # Fee = 10,500 * 0.00045 = 4.725
        expect(position.exit_fee).to be_within(0.001).of(4.725)
      end

      it "calculates actual exit fee for closed positions" do
        position = build(:position, :closed, entry_price: 100_000, current_price: 110_000, size: 0.1)
        # Exit notional = 110,000 * 0.1 = 11,000
        # Fee = 11,000 * 0.00045 = 4.95
        expect(position.exit_fee).to be_within(0.001).of(4.95)
      end
    end

    describe "#total_fees" do
      it "returns sum of entry and exit fees" do
        position = build(:position, entry_price: 100_000, current_price: 100_000, size: 0.1)
        expect(position.total_fees).to be_within(0.01).of(9.0)
      end
    end

    describe "#net_pnl" do
      it "returns gross P&L minus trading fees for open positions" do
        # Gross PnL = 0.1 * (105,000 - 100,000) = 500
        # Fees = ~9.225 (entry + estimated exit)
        # Net = 500 - 9.225 = ~490.78
        position = build(:position, entry_price: 100_000, current_price: 105_000, size: 0.1, unrealized_pnl: 500)
        expect(position.net_pnl).to be_within(0.5).of(490.5)
      end

      it "returns gross P&L minus trading fees for closed positions" do
        # Realized PnL = 500
        # Fees = ~9.45 (entry + exit at 110k)
        # Net = 500 - 9.45 = ~490.55
        position = build(:position, :closed, entry_price: 100_000, current_price: 110_000, size: 0.1, realized_pnl: 500)
        expect(position.net_pnl).to be_within(0.5).of(490.5)
      end
    end

    describe "#fee_breakdown" do
      it "returns detailed fee information" do
        position = build(:position, entry_price: 100_000, size: 0.1)
        breakdown = position.fee_breakdown

        expect(breakdown).to include(:entry_fee, :exit_fee, :total_fee, :fee_rate, :estimated)
      end
    end
  end

  describe "decision relationships" do
    describe "#opening_decision" do
      it "returns the decision that opened the position" do
        position = create(:position)
        open_decision = create(:trading_decision, operation: "open")
        create(:order, trading_decision: open_decision, position: position)

        expect(position.opening_decision).to eq(open_decision)
      end

      it "returns nil when no opening decision exists" do
        position = create(:position)
        expect(position.opening_decision).to be_nil
      end

      it "does not return close decisions" do
        position = create(:position)
        close_decision = create(:trading_decision, operation: "close")
        create(:order, trading_decision: close_decision, position: position)

        expect(position.opening_decision).to be_nil
      end
    end

    describe "#closing_decision" do
      it "returns the decision that closed the position" do
        position = create(:position, :closed)
        close_decision = create(:trading_decision, operation: "close")
        create(:order, trading_decision: close_decision, position: position)

        expect(position.closing_decision).to eq(close_decision)
      end

      it "returns nil when no closing decision exists" do
        position = create(:position)
        expect(position.closing_decision).to be_nil
      end

      it "does not return open decisions" do
        position = create(:position)
        open_decision = create(:trading_decision, operation: "open")
        create(:order, trading_decision: open_decision, position: position)

        expect(position.closing_decision).to be_nil
      end
    end

    describe "full trade lifecycle" do
      it "returns both opening and closing decisions" do
        position = create(:position, :closed)

        open_decision = create(:trading_decision, operation: "open")
        close_decision = create(:trading_decision, operation: "close")

        create(:order, trading_decision: open_decision, position: position)
        create(:order, trading_decision: close_decision, position: position)

        expect(position.opening_decision).to eq(open_decision)
        expect(position.closing_decision).to eq(close_decision)
      end
    end
  end
end
