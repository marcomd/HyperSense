# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ExecutionLogs", type: :request do
  describe "GET /api/v1/execution_logs" do
    before do
      create(:execution_log, :place_order, status: "success", executed_at: 1.hour.ago)
      create(:execution_log, :cancel_order, status: "success", executed_at: 2.hours.ago)
      create(:execution_log, :sync_position, status: "failure", executed_at: 3.hours.ago)
    end

    it "returns all execution logs" do
      get "/api/v1/execution_logs"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_logs"].size).to eq(3)
      expect(json).to have_key("meta")
      expect(json["meta"]["total"]).to eq(3)
    end

    it "filters by status" do
      get "/api/v1/execution_logs", params: { status: "success" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_logs"].size).to eq(2)
      expect(json["execution_logs"].map { |l| l["status"] }).to all(eq("success"))
    end

    it "filters by action" do
      get "/api/v1/execution_logs", params: { log_action: "place_order" }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_logs"].size).to eq(1)
      expect(json["execution_logs"].first["action"]).to eq("place_order")
    end

    it "filters by date range" do
      get "/api/v1/execution_logs", params: {
        start_date: 2.5.hours.ago.iso8601,
        end_date: 30.minutes.ago.iso8601
      }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_logs"].size).to eq(2)
    end

    it "paginates results" do
      get "/api/v1/execution_logs", params: { page: 1, per_page: 2 }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_logs"].size).to eq(2)
      expect(json["meta"]["page"]).to eq(1)
      expect(json["meta"]["per_page"]).to eq(2)
      expect(json["meta"]["total_pages"]).to eq(2)
    end

    it "returns logs ordered by executed_at descending" do
      get "/api/v1/execution_logs"

      json = response.parsed_body
      executed_ats = json["execution_logs"].map { |l| Time.zone.parse(l["executed_at"]) }

      expect(executed_ats).to eq(executed_ats.sort.reverse)
    end
  end

  describe "GET /api/v1/execution_logs/:id" do
    let(:execution_log) do
      create(:execution_log, :place_order, :with_duration, status: "success")
    end

    it "returns detailed execution log data" do
      get "/api/v1/execution_logs/#{execution_log.id}"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["execution_log"]["id"]).to eq(execution_log.id)
      expect(json["execution_log"]["action"]).to eq("place_order")
      expect(json["execution_log"]["status"]).to eq("success")
      expect(json["execution_log"]).to have_key("request_payload")
      expect(json["execution_log"]).to have_key("response_payload")
      expect(json["execution_log"]).to have_key("duration_ms")
    end

    it "returns 404 for non-existent execution log" do
      get "/api/v1/execution_logs/99999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/execution_logs/stats" do
    before do
      create(:execution_log, :place_order, status: "success", executed_at: 1.hour.ago)
      create(:execution_log, :cancel_order, status: "success", executed_at: 2.hours.ago)
      create(:execution_log, :sync_position, :failure, executed_at: 3.hours.ago)
      create(:execution_log, :sync_account, status: "success", executed_at: 25.hours.ago)
    end

    it "returns statistics for the default period" do
      get "/api/v1/execution_logs/stats"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["period_hours"]).to eq(24)
      expect(json["total_logs"]).to eq(3)
      expect(json["by_status"]["success"]).to eq(2)
      expect(json["by_status"]["failure"]).to eq(1)
      expect(json["by_action"]["place_order"]).to eq(1)
      expect(json["success_rate"]).to eq(66.67)
    end

    it "returns statistics for a custom period" do
      get "/api/v1/execution_logs/stats", params: { hours: 48 }

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json["period_hours"]).to eq(48)
      expect(json["total_logs"]).to eq(4)
    end

    it "clamps hours to valid range" do
      get "/api/v1/execution_logs/stats", params: { hours: 500 }

      json = response.parsed_body
      expect(json["period_hours"]).to eq(168)
    end
  end
end
