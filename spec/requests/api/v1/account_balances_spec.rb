# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AccountBalances", type: :request do
  describe "GET /api/v1/account_balances" do
    before do
      create(:account_balance, :initial, balance: 10_000, recorded_at: 3.days.ago)
      create(:account_balance, :sync, balance: 10_500, recorded_at: 2.days.ago)
      create(:account_balance, :deposit, balance: 15_500, recorded_at: 1.day.ago)
    end

    it "returns account balances with pagination" do
      get "/api/v1/account_balances"

      expect(response).to have_http_status(:success)
      json = response.parsed_body

      expect(json).to have_key("account_balances")
      expect(json).to have_key("meta")
      expect(json["account_balances"].count).to eq(3)
    end

    it "includes balance fields in response" do
      get "/api/v1/account_balances"

      json = response.parsed_body
      balance = json["account_balances"].first

      expect(balance).to have_key("id")
      expect(balance).to have_key("balance")
      expect(balance).to have_key("previous_balance")
      expect(balance).to have_key("delta")
      expect(balance).to have_key("event_type")
      expect(balance).to have_key("source")
      expect(balance).to have_key("notes")
      expect(balance).to have_key("recorded_at")
      expect(balance).to have_key("created_at")
    end

    it "orders by recorded_at descending (most recent first)" do
      get "/api/v1/account_balances"

      json = response.parsed_body
      balances = json["account_balances"]

      expect(balances.first["event_type"]).to eq("deposit")
      expect(balances.last["event_type"]).to eq("initial")
    end

    context "filtering by event_type" do
      it "filters balances by event_type" do
        get "/api/v1/account_balances", params: { event_type: "deposit" }

        json = response.parsed_body
        expect(json["account_balances"].count).to eq(1)
        expect(json["account_balances"].first["event_type"]).to eq("deposit")
      end
    end

    context "filtering by date range" do
      it "filters balances by from date" do
        get "/api/v1/account_balances", params: { from: 1.5.days.ago.iso8601 }

        json = response.parsed_body
        expect(json["account_balances"].count).to eq(1)
        expect(json["account_balances"].first["event_type"]).to eq("deposit")
      end

      it "filters balances by to date" do
        get "/api/v1/account_balances", params: { to: 2.5.days.ago.iso8601 }

        json = response.parsed_body
        expect(json["account_balances"].count).to eq(1)
        expect(json["account_balances"].first["event_type"]).to eq("initial")
      end

      it "filters balances by date range" do
        get "/api/v1/account_balances", params: {
          from: 2.5.days.ago.iso8601,
          to: 1.5.days.ago.iso8601
        }

        json = response.parsed_body
        expect(json["account_balances"].count).to eq(1)
        expect(json["account_balances"].first["event_type"]).to eq("sync")
      end
    end

    context "pagination" do
      before do
        create_list(:account_balance, 30)
      end

      it "returns paginated results" do
        get "/api/v1/account_balances", params: { page: 1, per_page: 10 }

        json = response.parsed_body
        expect(json["account_balances"].count).to eq(10)
        expect(json["meta"]["page"]).to eq(1)
        expect(json["meta"]["per_page"]).to eq(10)
        expect(json["meta"]["total"]).to eq(33) # 30 + 3 from before
      end
    end
  end

  describe "GET /api/v1/account_balances/:id" do
    let!(:balance) do
      create(:account_balance, :deposit, :with_hyperliquid_data,
        balance: 15_000,
        previous_balance: 10_000,
        delta: 5_000,
        notes: "Large deposit detected")
    end

    it "returns balance details" do
      get "/api/v1/account_balances/#{balance.id}"

      expect(response).to have_http_status(:success)
      json = response.parsed_body["account_balance"]

      expect(json["id"]).to eq(balance.id)
      expect(json["balance"]).to eq(15_000.0)
      expect(json["event_type"]).to eq("deposit")
    end

    it "includes detailed fields" do
      get "/api/v1/account_balances/#{balance.id}"

      json = response.parsed_body["account_balance"]

      expect(json).to have_key("hyperliquid_data")
      expect(json).to have_key("updated_at")
      expect(json["hyperliquid_data"]).to be_a(Hash)
    end

    it "returns 404 for non-existent balance" do
      get "/api/v1/account_balances/999999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/account_balances/summary" do
    context "with balance history" do
      before do
        create(:account_balance, :initial, balance: 10_000, recorded_at: 5.days.ago)
        create(:account_balance, :deposit, balance: 15_000, delta: 5_000, recorded_at: 3.days.ago)
        create(:account_balance, :withdrawal, balance: 12_000, delta: -3_000, recorded_at: 2.days.ago)
        create(:account_balance, :sync, balance: 14_000, delta: 2_000, recorded_at: 1.hour.ago)
      end

      it "returns balance summary" do
        get "/api/v1/account_balances/summary"

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json).to have_key("initial_balance")
        expect(json).to have_key("current_balance")
        expect(json).to have_key("total_deposits")
        expect(json).to have_key("total_withdrawals")
        expect(json).to have_key("calculated_pnl")
        expect(json).to have_key("last_sync")
        expect(json).to have_key("record_count")
        expect(json).to have_key("deposits_count")
        expect(json).to have_key("withdrawals_count")
      end

      it "calculates values correctly" do
        get "/api/v1/account_balances/summary"

        json = response.parsed_body

        expect(json["initial_balance"]).to eq(10_000.0)
        expect(json["current_balance"]).to eq(14_000.0)
        expect(json["total_deposits"]).to eq(5_000.0)
        expect(json["total_withdrawals"]).to eq(3_000.0)
        # calculated_pnl = current - initial - deposits + withdrawals
        # = 14000 - 10000 - 5000 + 3000 = 2000
        expect(json["calculated_pnl"]).to eq(2_000.0)
      end

      it "includes counts" do
        get "/api/v1/account_balances/summary"

        json = response.parsed_body

        expect(json["record_count"]).to eq(4)
        expect(json["deposits_count"]).to eq(1)
        expect(json["withdrawals_count"]).to eq(1)
      end
    end

    context "with no balance history" do
      it "returns null values" do
        get "/api/v1/account_balances/summary"

        expect(response).to have_http_status(:success)
        json = response.parsed_body

        expect(json["initial_balance"]).to be_nil
        expect(json["current_balance"]).to be_nil
        expect(json["calculated_pnl"]).to eq(0.0)
        expect(json["record_count"]).to eq(0)
      end
    end

    context "with only initial balance" do
      before do
        create(:account_balance, :initial, balance: 10_000)
      end

      it "returns initial as both initial and current balance" do
        get "/api/v1/account_balances/summary"

        json = response.parsed_body

        expect(json["initial_balance"]).to eq(10_000.0)
        expect(json["current_balance"]).to eq(10_000.0)
        expect(json["calculated_pnl"]).to eq(0.0)
      end
    end
  end
end
