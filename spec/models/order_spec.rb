# frozen_string_literal: true

require "rails_helper"

RSpec.describe Order do
  describe "associations" do
    it "belongs to trading_decision optionally" do
      order = build(:order, trading_decision: nil)
      expect(order).to be_valid
    end

    it "belongs to position optionally" do
      order = build(:order, position: nil)
      expect(order).to be_valid
    end

    it "has many execution_logs as loggable" do
      order = create(:order)
      log = create(:execution_log, loggable: order)
      expect(order.execution_logs).to include(log)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      order = build(:order)
      expect(order).to be_valid
    end

    it "requires symbol" do
      order = build(:order, symbol: nil)
      expect(order).not_to be_valid
      expect(order.errors[:symbol]).to include("can't be blank")
    end

    it "requires order_type" do
      order = build(:order, order_type: nil)
      expect(order).not_to be_valid
      expect(order.errors[:order_type]).to include("can't be blank")
    end

    it "requires order_type to be market, limit, or stop_limit" do
      # Market order - no price required
      order = build(:order, order_type: "market")
      expect(order).to be_valid

      # Limit order - requires price
      order = build(:order, order_type: "limit", price: 100_000)
      expect(order).to be_valid

      # Stop limit order - requires both price and stop_price
      order = build(:order, order_type: "stop_limit", price: 100_000, stop_price: 99_000)
      expect(order).to be_valid

      order = build(:order, order_type: "invalid")
      expect(order).not_to be_valid
      expect(order.errors[:order_type]).to include("is not included in the list")
    end

    it "requires side to be buy or sell" do
      %w[buy sell].each do |valid_side|
        order = build(:order, side: valid_side)
        expect(order).to be_valid
      end

      order = build(:order, side: "invalid")
      expect(order).not_to be_valid
      expect(order.errors[:side]).to include("is not included in the list")
    end

    it "requires status to be a valid value" do
      %w[pending submitted filled partially_filled cancelled failed].each do |valid_status|
        order = build(:order, status: valid_status)
        expect(order).to be_valid
      end

      order = build(:order, status: "invalid")
      expect(order).not_to be_valid
      expect(order.errors[:status]).to include("is not included in the list")
    end

    it "requires size to be greater than 0" do
      order = build(:order, size: 0)
      expect(order).not_to be_valid

      order = build(:order, size: 0.001)
      expect(order).to be_valid
    end

    it "requires price for limit orders" do
      order = build(:order, order_type: "limit", price: nil)
      expect(order).not_to be_valid
      expect(order.errors[:price]).to include("can't be blank")
    end

    it "does not require price for market orders" do
      order = build(:order, order_type: "market", price: nil)
      expect(order).to be_valid
    end

    it "requires stop_price for stop_limit orders" do
      order = build(:order, order_type: "stop_limit", stop_price: nil)
      expect(order).not_to be_valid
      expect(order.errors[:stop_price]).to include("can't be blank")
    end
  end

  describe "scopes" do
    describe ".pending" do
      it "returns orders with pending status" do
        pending_order = create(:order, status: "pending")
        _filled_order = create(:order, :filled)

        expect(Order.pending).to contain_exactly(pending_order)
      end
    end

    describe ".submitted" do
      it "returns orders with submitted status" do
        submitted_order = create(:order, status: "submitted")
        _pending_order = create(:order, status: "pending")

        expect(Order.submitted).to contain_exactly(submitted_order)
      end
    end

    describe ".filled" do
      it "returns orders with filled status" do
        filled_order = create(:order, :filled)
        _pending_order = create(:order, status: "pending")

        expect(Order.filled).to contain_exactly(filled_order)
      end
    end

    describe ".active" do
      it "returns pending and submitted orders" do
        pending_order = create(:order, status: "pending")
        submitted_order = create(:order, status: "submitted")
        _filled_order = create(:order, :filled)

        expect(Order.active).to contain_exactly(pending_order, submitted_order)
      end
    end

    describe ".for_symbol" do
      it "filters by symbol" do
        btc_order = create(:order, symbol: "BTC")
        _eth_order = create(:order, symbol: "ETH")

        expect(Order.for_symbol("BTC")).to contain_exactly(btc_order)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        older = create(:order, created_at: 2.hours.ago)
        newer = create(:order, created_at: 1.hour.ago)

        expect(Order.recent.first).to eq(newer)
        expect(Order.recent.last).to eq(older)
      end
    end

    describe ".buys" do
      it "returns only buy orders" do
        buy_order = create(:order, side: "buy")
        _sell_order = create(:order, side: "sell")

        expect(Order.buys).to contain_exactly(buy_order)
      end
    end

    describe ".sells" do
      it "returns only sell orders" do
        _buy_order = create(:order, side: "buy")
        sell_order = create(:order, side: "sell")

        expect(Order.sells).to contain_exactly(sell_order)
      end
    end
  end

  describe "state transitions" do
    describe "#submit!" do
      it "sets status to submitted and records submitted_at" do
        order = create(:order, status: "pending")

        freeze_time do
          order.submit!("HL-12345")
          order.reload

          expect(order.status).to eq("submitted")
          expect(order.hyperliquid_order_id).to eq("HL-12345")
          expect(order.submitted_at).to eq(Time.current)
        end
      end
    end

    describe "#fill!" do
      it "sets status to filled with fill details" do
        order = create(:order, status: "submitted", size: 0.1)

        freeze_time do
          order.fill!(filled_size: 0.1, average_price: 100_500)
          order.reload

          expect(order.status).to eq("filled")
          expect(order.filled_size).to eq(0.1)
          expect(order.average_fill_price).to eq(100_500)
          expect(order.filled_at).to eq(Time.current)
        end
      end
    end

    describe "#partially_fill!" do
      it "sets status to partially_filled" do
        order = create(:order, status: "submitted", size: 0.1)
        order.partially_fill!(filled_size: 0.05, average_price: 100_500)
        order.reload

        expect(order.status).to eq("partially_filled")
        expect(order.filled_size).to eq(0.05)
        expect(order.average_fill_price).to eq(100_500)
      end
    end

    describe "#cancel!" do
      it "sets status to cancelled" do
        order = create(:order, status: "submitted")
        order.cancel!
        expect(order.reload.status).to eq("cancelled")
      end

      it "accepts a reason" do
        order = create(:order, status: "submitted")
        order.cancel!(reason: "User requested")
        order.reload

        expect(order.status).to eq("cancelled")
        expect(order.hyperliquid_response).to include("cancel_reason" => "User requested")
      end
    end

    describe "#fail!" do
      it "sets status to failed with error message" do
        order = create(:order, status: "pending")
        order.fail!("API connection error")
        order.reload

        expect(order.status).to eq("failed")
        expect(order.hyperliquid_response).to include("error" => "API connection error")
      end
    end
  end

  describe "helper methods" do
    describe "#pending?" do
      it "returns true when status is pending" do
        order = build(:order, status: "pending")
        expect(order.pending?).to be true
      end
    end

    describe "#filled?" do
      it "returns true when status is filled" do
        order = build(:order, :filled)
        expect(order.filled?).to be true
      end
    end

    describe "#active?" do
      it "returns true when status is pending or submitted" do
        expect(build(:order, status: "pending").active?).to be true
        expect(build(:order, status: "submitted").active?).to be true
        expect(build(:order, :filled).active?).to be false
      end
    end

    describe "#buy?" do
      it "returns true when side is buy" do
        order = build(:order, side: "buy")
        expect(order.buy?).to be true
      end
    end

    describe "#sell?" do
      it "returns true when side is sell" do
        order = build(:order, side: "sell")
        expect(order.sell?).to be true
      end
    end

    describe "#market_order?" do
      it "returns true when order_type is market" do
        order = build(:order, order_type: "market")
        expect(order.market_order?).to be true
      end
    end

    describe "#limit_order?" do
      it "returns true when order_type is limit" do
        order = build(:order, :limit_order)
        expect(order.limit_order?).to be true
      end
    end

    describe "#remaining_size" do
      it "calculates unfilled size" do
        order = build(:order, size: 0.1, filled_size: 0.03)
        expect(order.remaining_size).to eq(0.07)
      end

      it "returns full size when nothing filled" do
        order = build(:order, size: 0.1, filled_size: nil)
        expect(order.remaining_size).to eq(0.1)
      end
    end

    describe "#fill_percent" do
      it "calculates percentage filled" do
        order = build(:order, size: 0.1, filled_size: 0.05)
        expect(order.fill_percent).to eq(50.0)
      end

      it "returns 0 when nothing filled" do
        order = build(:order, size: 0.1, filled_size: nil)
        expect(order.fill_percent).to eq(0)
      end
    end
  end
end
