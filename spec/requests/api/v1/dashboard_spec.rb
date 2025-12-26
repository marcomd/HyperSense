# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Dashboard", type: :request do
  describe "GET /api/v1/dashboard" do
    before do
      # Create some test data
      create(:market_snapshot, symbol: "BTC", price: 100_000, captured_at: 1.minute.ago)
      create(:market_snapshot, symbol: "ETH", price: 3500, captured_at: 1.minute.ago)
      create(:position, symbol: "BTC", entry_price: 95_000, current_price: 100_000)
      create(:macro_strategy, bias: "bullish", valid_until: 1.day.from_now)
      create(:trading_decision, symbol: "BTC", operation: "hold", status: "executed")
    end

    it "returns aggregated dashboard data" do
      get "/api/v1/dashboard"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("account")
      expect(json).to have_key("positions")
      expect(json).to have_key("market")
      expect(json).to have_key("macro_strategy")
      expect(json).to have_key("recent_decisions")
      expect(json).to have_key("system_status")
    end

    it "includes account summary" do
      get "/api/v1/dashboard"

      json = response.parsed_body
      account = json["account"]

      expect(account["open_positions_count"]).to eq(1)
      expect(account).to have_key("total_unrealized_pnl")
      expect(account).to have_key("paper_trading")
      expect(account).to have_key("circuit_breaker")
    end

    it "includes market overview" do
      get "/api/v1/dashboard"

      json = response.parsed_body
      market = json["market"]

      expect(market).to have_key("BTC")
      expect(market).to have_key("ETH")
      expect(market["BTC"]["price"]).to eq(100_000.0)
    end
  end

  describe "GET /api/v1/dashboard/account" do
    it "returns account summary only" do
      create(:position, symbol: "BTC")

      get "/api/v1/dashboard/account"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("account")
      expect(json["account"]["open_positions_count"]).to eq(1)
    end
  end

  describe "GET /api/v1/dashboard/system_status" do
    it "returns system status" do
      get "/api/v1/dashboard/system_status"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("system")
      expect(json["system"]).to have_key("market_data")
      expect(json["system"]).to have_key("trading_cycle")
      expect(json["system"]).to have_key("macro_strategy")
    end
  end
end
