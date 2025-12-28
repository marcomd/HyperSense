# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::AccountManager do
  let(:manager) { described_class.new }
  let(:mock_client) { instance_double(Execution::HyperliquidClient) }
  let(:test_address) { "0x1234567890abcdef1234567890abcdef12345678" }

  before do
    allow(Execution::HyperliquidClient).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:address).and_return(test_address)
    allow(mock_client).to receive(:configured?).and_return(true)
  end

  describe "#fetch_account_state" do
    let(:hyperliquid_response) do
      {
        "crossMarginSummary" => {
          "accountValue" => "10000.0",
          "totalMarginUsed" => "2000.0",
          "totalNtlPos" => "5000.0",
          "totalRawUsd" => "8000.0"
        },
        "assetPositions" => [
          {
            "position" => {
              "coin" => "BTC",
              "szi" => "0.1",
              "entryPx" => "100000.0",
              "unrealizedPnl" => "500.0"
            }
          }
        ]
      }
    end

    before do
      allow(mock_client).to receive(:user_state).and_return(hyperliquid_response)
    end

    it "returns formatted account state" do
      result = manager.fetch_account_state

      expect(result).to include(
        account_value: 10_000.0,
        margin_used: 2_000.0,
        available_margin: 8_000.0,
        positions_count: 1
      )
    end

    it "calculates available margin correctly" do
      result = manager.fetch_account_state

      expect(result[:available_margin]).to eq(8_000.0)
    end

    it "creates an execution log on success" do
      expect { manager.fetch_account_state }
        .to change { ExecutionLog.count }.by(1)

      log = ExecutionLog.last
      expect(log.action).to eq("sync_account")
      expect(log.status).to eq("success")
    end

    context "when API fails" do
      before do
        allow(mock_client).to receive(:user_state)
          .and_raise(Execution::HyperliquidClient::HyperliquidApiError, "Connection failed")
      end

      it "creates a failure log" do
        expect { manager.fetch_account_state rescue nil }
          .to change { ExecutionLog.failed.count }.by(1)
      end

      it "raises the error" do
        expect { manager.fetch_account_state }
          .to raise_error(Execution::HyperliquidClient::HyperliquidApiError)
      end
    end
  end

  describe "#get_portfolio_summary" do
    before do
      allow(mock_client).to receive(:user_state).and_return({
        "crossMarginSummary" => {
          "accountValue" => "10000.0",
          "totalMarginUsed" => "2000.0",
          "totalRawUsd" => "8000.0"
        },
        "assetPositions" => []
      })
    end

    it "returns summary including local positions" do
      create(:position, status: "open", symbol: "BTC", unrealized_pnl: 100)
      create(:position, status: "open", symbol: "ETH", unrealized_pnl: -50)

      result = manager.get_portfolio_summary

      expect(result[:open_positions]).to eq(2)
      expect(result[:total_unrealized_pnl]).to eq(50)
    end

    it "includes account state from Hyperliquid" do
      result = manager.get_portfolio_summary

      expect(result[:account_value]).to eq(10_000.0)
      expect(result[:available_margin]).to eq(8_000.0)
    end
  end

  describe "#can_trade?" do
    context "when Hyperliquid credentials are not configured" do
      before do
        allow(mock_client).to receive(:configured?).and_return(false)
      end

      it "raises ConfigurationError with clear message" do
        expect { manager.can_trade?(margin_required: 1000) }
          .to raise_error(
            Execution::HyperliquidClient::ConfigurationError,
            /Hyperliquid credentials not configured/
          )
      end

      it "includes setup instructions in error message" do
        expect { manager.can_trade?(margin_required: 1000) }
          .to raise_error(Execution::HyperliquidClient::ConfigurationError) do |error|
            expect(error.message).to include(".env")
          end
      end
    end

    context "when Hyperliquid is configured" do
      before do
        allow(mock_client).to receive(:user_state).and_return({
          "crossMarginSummary" => {
            "accountValue" => "10000.0",
            "totalMarginUsed" => "2000.0",
            "totalRawUsd" => "8000.0"
          },
          "assetPositions" => []
        })
      end

      it "returns true when margin is available" do
        expect(manager.can_trade?(margin_required: 1000)).to be true
      end

      it "returns false when insufficient margin" do
        expect(manager.can_trade?(margin_required: 9000)).to be false
      end

      it "checks position limits" do
        create_list(:position, 5, status: "open")

        allow(Settings.risk).to receive(:max_open_positions).and_return(5)

        expect(manager.can_trade?(margin_required: 100)).to be false
      end
    end
  end

  describe "#margin_for_position" do
    it "calculates required margin for a position" do
      result = manager.margin_for_position(
        size: 0.1,
        price: 100_000,
        leverage: 10
      )

      expect(result).to eq(1_000) # (0.1 * 100000) / 10
    end

    it "uses default leverage when not specified" do
      allow(Settings.risk).to receive(:default_leverage).and_return(5)

      result = manager.margin_for_position(
        size: 0.1,
        price: 100_000
      )

      expect(result).to eq(2_000) # (0.1 * 100000) / 5
    end
  end
end
