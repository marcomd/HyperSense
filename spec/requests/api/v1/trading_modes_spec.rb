# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::TradingModes", type: :request do
  before do
    # Clean up any existing modes
    TradingMode.delete_all
  end

  describe "GET /api/v1/trading_mode/current" do
    it "returns the current mode with permissions" do
      create(:trading_mode, mode: "enabled")

      get "/api/v1/trading_mode/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("enabled")
      expect(json["mode"]["changed_by"]).to be_present
      expect(json["mode"]["updated_at"]).to be_present
      expect(json["can_open"]).to be true
      expect(json["can_close"]).to be true
    end

    it "returns exit_only mode with correct permissions" do
      create(:trading_mode, :exit_only)

      get "/api/v1/trading_mode/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("exit_only")
      expect(json["can_open"]).to be false
      expect(json["can_close"]).to be true
    end

    it "returns blocked mode with correct permissions" do
      create(:trading_mode, :blocked)

      get "/api/v1/trading_mode/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("blocked")
      expect(json["can_open"]).to be false
      expect(json["can_close"]).to be false
    end

    it "creates default enabled mode if none exists" do
      get "/api/v1/trading_mode/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("enabled")
      expect(TradingMode.count).to eq(1)
    end

    it "includes reason when set" do
      create(:trading_mode, :circuit_breaker_triggered)

      get "/api/v1/trading_mode/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("exit_only")
      expect(json["mode"]["reason"]).to eq("Daily loss exceeded 5%")
      expect(json["mode"]["changed_by"]).to eq("circuit_breaker")
    end
  end

  describe "PUT /api/v1/trading_mode/switch" do
    before do
      create(:trading_mode, mode: "enabled")
    end

    it "switches to exit_only mode" do
      put "/api/v1/trading_mode/switch", params: { mode: "exit_only" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("exit_only")
      expect(json["can_open"]).to be false
      expect(json["can_close"]).to be true
      expect(json["message"]).to include("exit_only")
      expect(TradingMode.current_mode).to eq("exit_only")
    end

    it "switches to blocked mode" do
      put "/api/v1/trading_mode/switch", params: { mode: "blocked" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("blocked")
      expect(json["can_open"]).to be false
      expect(json["can_close"]).to be false
      expect(TradingMode.current_mode).to eq("blocked")
    end

    it "switches back to enabled mode" do
      TradingMode.switch_to!("blocked")

      put "/api/v1/trading_mode/switch", params: { mode: "enabled" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["mode"]).to eq("enabled")
      expect(json["can_open"]).to be true
      expect(json["can_close"]).to be true
      expect(TradingMode.current_mode).to eq("enabled")
    end

    it "accepts optional reason parameter" do
      put "/api/v1/trading_mode/switch", params: { mode: "blocked", reason: "Manual halt for maintenance" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["mode"]["reason"]).to eq("Manual halt for maintenance")
      expect(TradingMode.current.reason).to eq("Manual halt for maintenance")
    end

    it "returns error for invalid mode" do
      put "/api/v1/trading_mode/switch", params: { mode: "invalid" }

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body

      expect(json["error"]).to include("Invalid mode")
      expect(json["error"]).to include("enabled, exit_only, blocked")
    end

    it "returns error when mode param is missing" do
      put "/api/v1/trading_mode/switch"

      expect(response).to have_http_status(:bad_request)
    end

    it "sets changed_by to dashboard" do
      put "/api/v1/trading_mode/switch", params: { mode: "exit_only" }

      expect(response).to have_http_status(:success)
      expect(TradingMode.current.changed_by).to eq("dashboard")
    end

    it "clears previous reason when switching without reason" do
      TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker", reason: "Daily loss exceeded")

      put "/api/v1/trading_mode/switch", params: { mode: "enabled" }

      expect(response).to have_http_status(:success)
      expect(TradingMode.current.reason).to be_nil
    end

    it "does not create new records when switching" do
      expect { put "/api/v1/trading_mode/switch", params: { mode: "blocked" } }
        .not_to change { TradingMode.count }
    end
  end
end
