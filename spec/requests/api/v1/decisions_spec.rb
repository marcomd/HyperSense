# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Decisions", type: :request do
  describe "GET /api/v1/decisions" do
    before do
      create(:trading_decision, symbol: "BTC", operation: "open", status: "executed")
      create(:trading_decision, symbol: "ETH", operation: "hold", status: "pending")
    end

    it "returns trading decisions with pagination" do
      get "/api/v1/decisions"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("decisions")
      expect(json).to have_key("meta")
      expect(json["decisions"].count).to eq(2)
    end

    it "includes volatility fields in response" do
      decision = create(:trading_decision,
        symbol: "BTC",
        volatility_level: :high,
        atr_value: 0.025,
        next_cycle_interval: 6)

      get "/api/v1/decisions"

      json = response.parsed_body
      found = json["decisions"].find { |d| d["id"] == decision.id }

      expect(found["volatility_level"]).to eq("high")
      expect(found["atr_value"]).to eq(0.025)
      expect(found["next_cycle_interval"]).to eq(6)
    end

    it "does not include llm_model in list serialization" do
      create(:trading_decision, symbol: "BTC", llm_model: "claude-sonnet-4-5")

      get "/api/v1/decisions"

      json = response.parsed_body
      decision = json["decisions"].first

      expect(decision).not_to have_key("llm_model")
    end

    context "filtering by volatility_level" do
      before do
        create(:trading_decision, symbol: "BTC", volatility_level: :very_high)
        create(:trading_decision, symbol: "ETH", volatility_level: :low)
      end

      it "filters decisions by volatility_level" do
        get "/api/v1/decisions", params: { volatility_level: "very_high" }

        json = response.parsed_body
        expect(json["decisions"].count).to eq(1)
        expect(json["decisions"].first["volatility_level"]).to eq("very_high")
      end

      it "returns all decisions when volatility_level not specified" do
        get "/api/v1/decisions"

        json = response.parsed_body
        # 2 from before + 2 from context = 4
        expect(json["decisions"].count).to eq(4)
      end
    end

    context "filtering by status" do
      it "filters decisions by status" do
        get "/api/v1/decisions", params: { status: "executed" }

        json = response.parsed_body
        expect(json["decisions"].count).to eq(1)
        expect(json["decisions"].first["status"]).to eq("executed")
      end
    end

    context "filtering by symbol" do
      it "filters decisions by symbol" do
        get "/api/v1/decisions", params: { symbol: "btc" }

        json = response.parsed_body
        expect(json["decisions"].count).to eq(1)
        expect(json["decisions"].first["symbol"]).to eq("BTC")
      end
    end
  end

  describe "GET /api/v1/decisions/:id" do
    let!(:decision) do
      create(:trading_decision,
        symbol: "BTC",
        llm_model: "claude-sonnet-4-5",
        volatility_level: :high,
        atr_value: 0.025,
        next_cycle_interval: 6)
    end

    it "returns decision details" do
      get "/api/v1/decisions/#{decision.id}"

      expect(response).to have_http_status(:success)
      json = response.parsed_body["decision"]

      expect(json["id"]).to eq(decision.id)
      expect(json["symbol"]).to eq("BTC")
    end

    it "includes llm_model in detailed response" do
      get "/api/v1/decisions/#{decision.id}"

      json = response.parsed_body["decision"]

      expect(json).to have_key("llm_model")
      expect(json["llm_model"]).to eq("claude-sonnet-4-5")
    end

    it "includes volatility fields in detailed response" do
      get "/api/v1/decisions/#{decision.id}"

      json = response.parsed_body["decision"]

      expect(json["volatility_level"]).to eq("high")
      expect(json["atr_value"]).to eq(0.025)
      expect(json["next_cycle_interval"]).to eq(6)
    end

    it "includes context_sent and llm_response in detailed response" do
      get "/api/v1/decisions/#{decision.id}"

      json = response.parsed_body["decision"]

      expect(json).to have_key("context_sent")
      expect(json).to have_key("llm_response")
      expect(json).to have_key("parsed_decision")
    end
  end

  describe "GET /api/v1/decisions/recent" do
    before do
      5.times { |i| create(:trading_decision, symbol: "BTC", created_at: i.minutes.ago) }
    end

    it "returns recent decisions" do
      get "/api/v1/decisions/recent"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["decisions"].count).to eq(5)
    end

    it "respects limit parameter" do
      get "/api/v1/decisions/recent", params: { limit: 3 }

      json = response.parsed_body
      expect(json["decisions"].count).to eq(3)
    end

    it "includes volatility fields" do
      decision = create(:trading_decision,
        symbol: "ETH",
        volatility_level: :medium,
        atr_value: 0.015,
        next_cycle_interval: 12)

      get "/api/v1/decisions/recent", params: { limit: 10 }

      json = response.parsed_body
      found = json["decisions"].find { |d| d["id"] == decision.id }

      expect(found["volatility_level"]).to eq("medium")
      expect(found["atr_value"]).to eq(0.015)
      expect(found["next_cycle_interval"]).to eq(12)
    end
  end

  describe "GET /api/v1/decisions/stats" do
    before do
      create(:trading_decision, status: "executed", operation: "open")
      create(:trading_decision, status: "rejected", operation: "open")
      create(:trading_decision, :hold, status: "executed")
    end

    it "returns decision statistics" do
      get "/api/v1/decisions/stats"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("period_hours")
      expect(json).to have_key("total_decisions")
      expect(json).to have_key("by_status")
      expect(json).to have_key("by_operation")
      expect(json).to have_key("execution_rate")
    end
  end
end
