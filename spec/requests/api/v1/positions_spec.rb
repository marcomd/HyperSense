# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Positions", type: :request do
  describe "GET /api/v1/positions" do
    before do
      create(:position, symbol: "BTC", entry_price: 95_000)
      create(:position, symbol: "ETH", entry_price: 3500)
      create(:position, :closed, symbol: "SOL", entry_price: 180)
    end

    it "returns all positions" do
      get "/api/v1/positions"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["positions"].size).to eq(3)
      expect(json).to have_key("meta")
      expect(json["meta"]["total"]).to eq(3)
    end

    it "filters by status" do
      get "/api/v1/positions", params: { status: "open" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["positions"].size).to eq(2)
      expect(json["positions"].map { |p| p["status"] }).to all(eq("open"))
    end

    it "filters by symbol" do
      get "/api/v1/positions", params: { symbol: "BTC" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["positions"].size).to eq(1)
      expect(json["positions"].first["symbol"]).to eq("BTC")
    end

    it "paginates results" do
      get "/api/v1/positions", params: { page: 1, per_page: 2 }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["positions"].size).to eq(2)
      expect(json["meta"]["page"]).to eq(1)
      expect(json["meta"]["per_page"]).to eq(2)
      expect(json["meta"]["total_pages"]).to eq(2)
    end
  end

  describe "GET /api/v1/positions/open" do
    before do
      create(:position, symbol: "BTC", entry_price: 95_000, unrealized_pnl: 500)
      create(:position, symbol: "ETH", entry_price: 3500, unrealized_pnl: -50)
      create(:position, :closed, symbol: "SOL", entry_price: 180)
    end

    it "returns only open positions with summary" do
      get "/api/v1/positions/open"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["positions"].size).to eq(2)
      expect(json["summary"]["count"]).to eq(2)
      expect(json["summary"]["total_pnl"]).to eq(450.0)
    end
  end

  describe "GET /api/v1/positions/:id" do
    let(:position) do
      create(:position, symbol: "BTC", entry_price: 95_000, stop_loss_price: 90_000)
    end

    it "returns detailed position data" do
      get "/api/v1/positions/#{position.id}"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["position"]["id"]).to eq(position.id)
      expect(json["position"]["symbol"]).to eq("BTC")
      expect(json["position"]["stop_loss_price"]).to eq(90_000.0)
    end

    it "returns 404 for non-existent position" do
      get "/api/v1/positions/99999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/positions/performance" do
    before do
      create(:position, :closed, symbol: "BTC", realized_pnl: 500, closed_at: 1.day.ago)
      create(:position, :closed, symbol: "ETH", realized_pnl: -100, closed_at: 2.days.ago)
      create(:position, :closed, symbol: "SOL", realized_pnl: 200, closed_at: 3.days.ago)
    end

    it "returns equity curve and statistics" do
      get "/api/v1/positions/performance", params: { days: 7 }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("equity_curve")
      expect(json).to have_key("statistics")
      expect(json["statistics"]["total_trades"]).to eq(3)
      expect(json["statistics"]["wins"]).to eq(2)
      expect(json["statistics"]["losses"]).to eq(1)
    end
  end
end
