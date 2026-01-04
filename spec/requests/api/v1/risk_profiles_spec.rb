# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::RiskProfiles", type: :request do
  before do
    # Clean up any existing profiles
    RiskProfile.delete_all
  end

  describe "GET /api/v1/risk_profile/current" do
    it "returns the current profile with parameters" do
      create(:risk_profile, name: "moderate")

      get "/api/v1/risk_profile/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("moderate")
      expect(json["profile"]["changed_by"]).to be_present
      expect(json["profile"]["updated_at"]).to be_present
      expect(json["parameters"]["rsi_oversold"]).to eq(30)
      expect(json["parameters"]["rsi_overbought"]).to eq(70)
      expect(json["parameters"]["min_confidence"]).to eq(0.6)
    end

    it "returns cautious profile parameters when active" do
      create(:risk_profile, :cautious)

      get "/api/v1/risk_profile/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("cautious")
      expect(json["parameters"]["rsi_oversold"]).to eq(35)
      expect(json["parameters"]["rsi_overbought"]).to eq(65)
      expect(json["parameters"]["min_confidence"]).to eq(0.7)
      expect(json["parameters"]["default_leverage"]).to eq(2)
    end

    it "returns fearless profile parameters when active" do
      create(:risk_profile, :fearless)

      get "/api/v1/risk_profile/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("fearless")
      expect(json["parameters"]["rsi_oversold"]).to eq(25)
      expect(json["parameters"]["rsi_overbought"]).to eq(75)
      expect(json["parameters"]["min_confidence"]).to eq(0.5)
      expect(json["parameters"]["default_leverage"]).to eq(5)
    end

    it "creates default moderate profile if none exists" do
      get "/api/v1/risk_profile/current"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("moderate")
      expect(RiskProfile.count).to eq(1)
    end
  end

  describe "PUT /api/v1/risk_profile/switch" do
    before do
      create(:risk_profile, name: "moderate")
    end

    it "switches to cautious profile" do
      put "/api/v1/risk_profile/switch", params: { profile: "cautious" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("cautious")
      expect(json["parameters"]["rsi_oversold"]).to eq(35)
      expect(json["message"]).to include("cautious")
      expect(RiskProfile.current_name).to eq("cautious")
    end

    it "switches to fearless profile" do
      put "/api/v1/risk_profile/switch", params: { profile: "fearless" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("fearless")
      expect(json["parameters"]["min_confidence"]).to eq(0.5)
      expect(RiskProfile.current_name).to eq("fearless")
    end

    it "switches back to moderate profile" do
      RiskProfile.switch_to!("fearless")

      put "/api/v1/risk_profile/switch", params: { profile: "moderate" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["profile"]["name"]).to eq("moderate")
      expect(RiskProfile.current_name).to eq("moderate")
    end

    it "returns error for invalid profile" do
      put "/api/v1/risk_profile/switch", params: { profile: "invalid" }

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body

      expect(json["error"]).to include("Invalid profile")
      expect(json["error"]).to include("cautious, moderate, fearless")
    end

    it "returns error when profile param is missing" do
      put "/api/v1/risk_profile/switch"

      expect(response).to have_http_status(:bad_request)
    end

    it "sets changed_by to dashboard" do
      put "/api/v1/risk_profile/switch", params: { profile: "cautious" }

      expect(response).to have_http_status(:success)
      expect(RiskProfile.current.changed_by).to eq("dashboard")
    end

    it "does not create new records when switching" do
      expect { put "/api/v1/risk_profile/switch", params: { profile: "fearless" } }
        .not_to change { RiskProfile.count }
    end
  end

  describe "Dashboard integration" do
    it "includes risk_profile in dashboard response" do
      create(:risk_profile, name: "cautious")

      get "/api/v1/dashboard"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("risk_profile")
      expect(json["risk_profile"]["name"]).to eq("cautious")
      expect(json["risk_profile"]["parameters"]["min_confidence"]).to eq(0.7)
    end
  end
end
