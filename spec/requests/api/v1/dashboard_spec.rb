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
      expect(account).to have_key("total_realized_pnl")
      expect(account).to have_key("all_time_pnl")
      expect(account).to have_key("paper_trading")
      expect(account).to have_key("circuit_breaker")
      expect(account).to have_key("hyperliquid")
      expect(account).to have_key("testnet_mode")
    end

    it "calculates all-time PnL from positions" do
      # Create closed positions with realized PnL
      create(:position, :closed, symbol: "ETH", realized_pnl: 100.0)
      create(:position, :closed, symbol: "SOL", realized_pnl: -25.0)

      get "/api/v1/dashboard"

      json = response.parsed_body
      account = json["account"]

      # total_realized_pnl = 100 - 25 = 75
      expect(account["total_realized_pnl"]).to eq(75.0)
      # all_time_pnl = total_realized_pnl + total_unrealized_pnl (from open position)
      expect(account["all_time_pnl"]).to be_present
    end

    it "includes hyperliquid data when not configured" do
      # By default in tests, Hyperliquid is not configured
      get "/api/v1/dashboard"

      json = response.parsed_body
      account = json["account"]

      expect(account["hyperliquid"]["configured"]).to eq(false)
      expect(account["hyperliquid"]["balance"]).to be_nil
    end

    it "includes market overview" do
      get "/api/v1/dashboard"

      json = response.parsed_body
      market = json["market"]

      expect(market).to have_key("BTC")
      expect(market).to have_key("ETH")
      expect(market["BTC"]["price"]).to eq(100_000.0)
    end

    it "includes llm_model in recent_decisions" do
      decision = create(:trading_decision, symbol: "ETH", operation: "open", llm_model: "claude-sonnet-4-5")

      get "/api/v1/dashboard"

      json = response.parsed_body
      recent = json["recent_decisions"].find { |d| d["id"] == decision.id }

      expect(recent).to have_key("llm_model")
      expect(recent["llm_model"]).to eq("claude-sonnet-4-5")
    end

    it "includes llm_model in macro_strategy" do
      # Update the existing macro strategy instead of deleting
      MacroStrategy.update_all(llm_model: "gemini-2.0-flash", valid_until: 1.day.from_now)

      get "/api/v1/dashboard"

      json = response.parsed_body
      strategy = json["macro_strategy"]

      expect(strategy).to have_key("llm_model")
      expect(strategy["llm_model"]).to eq("gemini-2.0-flash")
    end

    it "includes volatility_info in account summary" do
      # Create the most recent decision with specific volatility
      create(:trading_decision,
        symbol: "ETH",
        volatility_level: :high,
        atr_value: 0.025,
        next_cycle_interval: 6,
        created_at: 1.second.from_now)

      get "/api/v1/dashboard"

      json = response.parsed_body
      account = json["account"]

      expect(account).to have_key("volatility_info")
      expect(account["volatility_info"]["volatility_level"]).to eq("high")
      expect(account["volatility_info"]["atr_value"]).to eq(0.025)
      expect(account["volatility_info"]["next_cycle_interval"]).to eq(6)
      expect(account["volatility_info"]).to have_key("next_cycle_at")
      expect(account["volatility_info"]).to have_key("last_decision_at")
    end

    it "returns nil volatility_info when no decisions exist" do
      TradingDecision.destroy_all

      get "/api/v1/dashboard"

      json = response.parsed_body
      account = json["account"]

      expect(account["volatility_info"]).to be_nil
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

    it "includes volatility_info from latest trading decision" do
      create(:trading_decision,
        symbol: "ETH",
        volatility_level: :very_high,
        atr_value: 0.035,
        next_cycle_interval: 3,
        created_at: 2.minutes.ago)

      get "/api/v1/dashboard/account"

      json = response.parsed_body
      account = json["account"]

      expect(account["volatility_info"]["volatility_level"]).to eq("very_high")
      expect(account["volatility_info"]["atr_value"]).to eq(0.035)
      expect(account["volatility_info"]["next_cycle_interval"]).to eq(3)
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
