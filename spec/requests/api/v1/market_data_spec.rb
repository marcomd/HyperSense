# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::MarketData", type: :request do
  describe "GET /api/v1/market_data/snapshots" do
    before do
      create(:market_snapshot, symbol: "BTC", price: 98_500, captured_at: 1.hour.ago)
      create(:market_snapshot, symbol: "ETH", price: 3_450, captured_at: 2.hours.ago)
      create(:market_snapshot, symbol: "BTC", price: 98_000, captured_at: 3.hours.ago)
    end

    it "returns paginated snapshots" do
      get "/api/v1/market_data/snapshots"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["snapshots"].size).to eq(3)
      expect(json).to have_key("meta")
      expect(json["meta"]["total"]).to eq(3)
      expect(json["meta"]["page"]).to eq(1)
    end

    it "filters by symbol" do
      get "/api/v1/market_data/snapshots", params: { symbol: "BTC" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["snapshots"].size).to eq(2)
      expect(json["snapshots"].map { |s| s["symbol"] }).to all(eq("BTC"))
    end

    it "filters by date range" do
      get "/api/v1/market_data/snapshots", params: {
        start_date: 2.hours.ago.iso8601,
        end_date: Time.current.iso8601
      }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["snapshots"].size).to eq(2)
    end

    it "paginates results" do
      get "/api/v1/market_data/snapshots", params: { page: 1, per_page: 2 }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["snapshots"].size).to eq(2)
      expect(json["meta"]["page"]).to eq(1)
      expect(json["meta"]["per_page"]).to eq(2)
      expect(json["meta"]["total_pages"]).to eq(2)
    end

    it "returns snapshot details" do
      get "/api/v1/market_data/snapshots"

      json = response.parsed_body
      snapshot = json["snapshots"].first

      expect(snapshot).to have_key("id")
      expect(snapshot).to have_key("symbol")
      expect(snapshot).to have_key("price")
      expect(snapshot).to have_key("rsi_signal")
      expect(snapshot).to have_key("macd_signal")
      expect(snapshot).to have_key("ema_status")
      expect(snapshot).to have_key("captured_at")
    end
  end

  describe "GET /api/v1/market_data/current" do
    before do
      create(:market_snapshot, symbol: "BTC", price: 98_500)
      create(:market_snapshot, symbol: "ETH", price: 3_450)
    end

    it "returns current market data for all assets" do
      get "/api/v1/market_data/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["assets"].size).to eq(2)
      expect(json).to have_key("updated_at")
    end
  end

  describe "GET /api/v1/market_data/forecasts" do
    context "without pagination params (aggregated format)" do
      it "returns forecasts grouped by symbol and timeframe" do
        get "/api/v1/market_data/forecasts"

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json).to have_key("forecasts")
        expect(json["forecasts"]).to be_a(Hash)
      end
    end

    context "with pagination params (list format)" do
      before do
        create(:forecast, symbol: "BTC", timeframe: "1h", current_price: 98_000, predicted_price: 99_000)
        create(:forecast, symbol: "BTC", timeframe: "15m", current_price: 98_000, predicted_price: 98_500)
        create(:forecast, symbol: "ETH", timeframe: "1h", current_price: 3_400, predicted_price: 3_500)
      end

      it "returns paginated forecasts list" do
        get "/api/v1/market_data/forecasts", params: { page: 1, per_page: 25 }

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json["forecasts"]).to be_an(Array)
        expect(json["forecasts"].size).to eq(3)
        expect(json).to have_key("meta")
        expect(json["meta"]["total"]).to eq(3)
      end

      it "filters by symbol" do
        get "/api/v1/market_data/forecasts", params: { page: 1, symbol: "BTC" }

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json["forecasts"].size).to eq(2)
        expect(json["forecasts"].map { |f| f["symbol"] }).to all(eq("BTC"))
      end

      it "filters by timeframe" do
        get "/api/v1/market_data/forecasts", params: { page: 1, timeframe: "1h" }

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json["forecasts"].size).to eq(2)
        expect(json["forecasts"].map { |f| f["timeframe"] }).to all(eq("1h"))
      end

      it "returns forecast details" do
        get "/api/v1/market_data/forecasts", params: { page: 1 }

        json = response.parsed_body
        forecast = json["forecasts"].first

        expect(forecast).to have_key("id")
        expect(forecast).to have_key("symbol")
        expect(forecast).to have_key("timeframe")
        expect(forecast).to have_key("current_price")
        expect(forecast).to have_key("predicted_price")
        expect(forecast).to have_key("direction")
        expect(forecast).to have_key("change_pct")
        expect(forecast).to have_key("created_at")
      end

      it "paginates results" do
        get "/api/v1/market_data/forecasts", params: { page: 1, per_page: 2 }

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json["forecasts"].size).to eq(2)
        expect(json["meta"]["page"]).to eq(1)
        expect(json["meta"]["per_page"]).to eq(2)
        expect(json["meta"]["total_pages"]).to eq(2)
      end
    end
  end
end
