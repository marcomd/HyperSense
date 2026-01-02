# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  describe "GET /api/v1/orders" do
    before do
      create(:order, symbol: "BTC", side: "buy", status: "pending")
      create(:order, :filled, symbol: "ETH", side: "sell")
    end

    it "returns orders with pagination" do
      get "/api/v1/orders"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("orders")
      expect(json).to have_key("meta")
      expect(json["orders"].count).to eq(2)
    end

    it "includes order details in response" do
      get "/api/v1/orders"

      json = response.parsed_body
      order = json["orders"].first

      expect(order).to have_key("id")
      expect(order).to have_key("symbol")
      expect(order).to have_key("side")
      expect(order).to have_key("order_type")
      expect(order).to have_key("size")
      expect(order).to have_key("status")
      expect(order).to have_key("fill_percent")
      expect(order).to have_key("created_at")
    end

    context "filtering by status" do
      it "filters orders by status" do
        get "/api/v1/orders", params: { status: "filled" }

        json = response.parsed_body
        expect(json["orders"].count).to eq(1)
        expect(json["orders"].first["status"]).to eq("filled")
      end
    end

    context "filtering by symbol" do
      it "filters orders by symbol (case-insensitive)" do
        get "/api/v1/orders", params: { symbol: "btc" }

        json = response.parsed_body
        expect(json["orders"].count).to eq(1)
        expect(json["orders"].first["symbol"]).to eq("BTC")
      end
    end

    context "filtering by side" do
      it "filters orders by side" do
        get "/api/v1/orders", params: { side: "buy" }

        json = response.parsed_body
        expect(json["orders"].count).to eq(1)
        expect(json["orders"].first["side"]).to eq("buy")
      end
    end

    context "filtering by order_type" do
      before do
        create(:order, :limit_order, symbol: "SOL")
      end

      it "filters orders by order_type" do
        get "/api/v1/orders", params: { order_type: "limit" }

        json = response.parsed_body
        expect(json["orders"].count).to eq(1)
        expect(json["orders"].first["order_type"]).to eq("limit")
      end
    end

    context "filtering by date range" do
      before do
        create(:order, symbol: "SOL", created_at: 3.days.ago)
      end

      it "filters orders by from date" do
        get "/api/v1/orders", params: { from: 1.day.ago.iso8601 }

        json = response.parsed_body
        expect(json["orders"].count).to eq(2) # Only BTC and ETH from before block
      end

      it "filters orders by to date" do
        get "/api/v1/orders", params: { to: 2.days.ago.iso8601 }

        json = response.parsed_body
        expect(json["orders"].count).to eq(1) # Only SOL from 3 days ago
      end
    end

    context "pagination" do
      before do
        create_list(:order, 30)
      end

      it "returns paginated results" do
        get "/api/v1/orders", params: { page: 1, per_page: 10 }

        json = response.parsed_body
        expect(json["orders"].count).to eq(10)
        expect(json["meta"]["page"]).to eq(1)
        expect(json["meta"]["per_page"]).to eq(10)
        expect(json["meta"]["total"]).to eq(32) # 30 + 2 from before
      end

      it "respects per_page limit of 100" do
        get "/api/v1/orders", params: { per_page: 200 }

        json = response.parsed_body
        expect(json["meta"]["per_page"]).to eq(100)
      end
    end
  end

  describe "GET /api/v1/orders/:id" do
    let!(:order) do
      create(:order, :filled, :limit_order, :with_trading_decision,
        symbol: "BTC",
        price: 100_000,
        average_fill_price: 100_050,
        hyperliquid_response: { "status" => "ok" })
    end

    it "returns order details" do
      get "/api/v1/orders/#{order.id}"

      expect(response).to have_http_status(:success)
      json = response.parsed_body["order"]

      expect(json["id"]).to eq(order.id)
      expect(json["symbol"]).to eq("BTC")
      expect(json["status"]).to eq("filled")
    end

    it "includes detailed fields" do
      get "/api/v1/orders/#{order.id}"

      json = response.parsed_body["order"]

      expect(json).to have_key("hyperliquid_response")
      expect(json).to have_key("trading_decision_id")
      expect(json).to have_key("position_id")
      expect(json).to have_key("remaining_size")
      expect(json).to have_key("updated_at")
    end

    it "includes linked trading decision summary" do
      get "/api/v1/orders/#{order.id}"

      json = response.parsed_body["order"]

      expect(json).to have_key("trading_decision")
      expect(json["trading_decision"]).to have_key("id")
      expect(json["trading_decision"]).to have_key("operation")
      expect(json["trading_decision"]).to have_key("direction")
    end

    it "returns 404 for non-existent order" do
      get "/api/v1/orders/999999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/orders/active" do
    before do
      create(:order, status: "pending", symbol: "BTC")
      create(:order, :submitted, symbol: "ETH")
      create(:order, :filled, symbol: "SOL")
      create(:order, :cancelled, symbol: "DOGE")
    end

    it "returns only active orders (pending and submitted)" do
      get "/api/v1/orders/active"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["orders"].count).to eq(2)
      statuses = json["orders"].map { |o| o["status"] }
      expect(statuses).to match_array(%w[pending submitted])
    end

    it "does not include filled or cancelled orders" do
      get "/api/v1/orders/active"

      json = response.parsed_body
      symbols = json["orders"].map { |o| o["symbol"] }

      expect(symbols).not_to include("SOL")
      expect(symbols).not_to include("DOGE")
    end
  end

  describe "GET /api/v1/orders/stats" do
    before do
      create(:order, status: "pending", side: "buy", order_type: "market", symbol: "BTC")
      create(:order, :submitted, side: "buy", symbol: "ETH")
      create(:order, :filled, side: "sell", symbol: "BTC")
      create(:order, :cancelled, :limit_order, side: "sell", symbol: "SOL")
      create(:order, :failed, symbol: "DOGE")
    end

    it "returns order statistics" do
      get "/api/v1/orders/stats"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("period_hours")
      expect(json).to have_key("total_orders")
      expect(json).to have_key("by_status")
      expect(json).to have_key("by_symbol")
      expect(json).to have_key("by_side")
      expect(json).to have_key("by_type")
      expect(json).to have_key("fill_rate")
      expect(json).to have_key("active_count")
    end

    it "counts orders by status correctly" do
      get "/api/v1/orders/stats"

      json = response.parsed_body
      expect(json["by_status"]["pending"]).to eq(1)
      expect(json["by_status"]["submitted"]).to eq(1)
      expect(json["by_status"]["filled"]).to eq(1)
      expect(json["by_status"]["cancelled"]).to eq(1)
      expect(json["by_status"]["failed"]).to eq(1)
    end

    it "counts orders by side correctly" do
      get "/api/v1/orders/stats"

      json = response.parsed_body
      # pending: buy, submitted: buy, filled: sell, cancelled: sell, failed: buy (default)
      expect(json["by_side"]["buy"]).to eq(3)
      expect(json["by_side"]["sell"]).to eq(2)
    end

    it "calculates fill rate correctly" do
      # 1 filled out of 2 fillable (filled + cancelled) = 50%
      get "/api/v1/orders/stats"

      json = response.parsed_body
      expect(json["fill_rate"]).to eq(50.0)
    end

    it "respects hours parameter" do
      create(:order, created_at: 48.hours.ago)

      get "/api/v1/orders/stats", params: { hours: 24 }

      json = response.parsed_body
      expect(json["total_orders"]).to eq(5) # Excludes the old order
    end

    it "clamps hours parameter to valid range" do
      get "/api/v1/orders/stats", params: { hours: 500 }

      json = response.parsed_body
      expect(json["period_hours"]).to eq(168) # Max is 168
    end
  end
end
