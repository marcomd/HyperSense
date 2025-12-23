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
        position = create(:position, status: "open")

        freeze_time do
          position.close!
          position.reload

          expect(position.status).to eq("closed")
          expect(position.closed_at).to eq(Time.current)
        end
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
end
