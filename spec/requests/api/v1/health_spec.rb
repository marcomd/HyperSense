# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Health", type: :request do
  describe "GET /api/v1/health" do
    it "returns health status with version info" do
      get "/api/v1/health"

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["status"]).to eq("ok")
      expect(json["version"]).to eq(Backend::VERSION)
      expect(json["environment"]).to eq("test")
      expect(json["timestamp"]).to be_present
    end
  end
end
