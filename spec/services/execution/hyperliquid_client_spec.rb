# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::HyperliquidClient do
  let(:client) { described_class.new }
  let(:test_address) { "0x1234567890abcdef1234567890abcdef12345678" }
  let(:test_private_key) { "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" }
  let(:mock_sdk) { instance_double(Hyperliquid::SDK) }
  let(:mock_info) { instance_double(Hyperliquid::Info) }
  let(:mock_exchange) { instance_double(Hyperliquid::Exchange) }

  before do
    allow(Hyperliquid::SDK).to receive(:new).and_return(mock_sdk)
    allow(mock_sdk).to receive(:info).and_return(mock_info)
    allow(mock_sdk).to receive(:exchange).and_return(mock_exchange)
  end

  describe "#initialize" do
    it "creates a client with testnet configuration by default" do
      expect(client).to be_a(described_class)
    end

    it "respects testnet setting from configuration" do
      allow(Settings.hyperliquid).to receive(:testnet).and_return(true)
      client = described_class.new
      expect(client.testnet?).to be true
    end
  end

  describe "#address" do
    it "returns the configured wallet address from ENV" do
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(test_address)

      expect(client.address).to eq(test_address)
    end

    it "raises error when address is not configured" do
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(nil)

      client = described_class.new
      expect { client.address }.to raise_error(Execution::HyperliquidClient::ConfigurationError)
    end
  end

  describe "#configured?" do
    it "returns true when ENV credentials are present" do
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(test_address)
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_PRIVATE_KEY", nil).and_return("abc123")

      expect(client.configured?).to be true
    end

    it "returns false when ENV credentials are missing" do
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("HYPERLIQUID_PRIVATE_KEY", nil).and_return(nil)

      expect(client.configured?).to be false
    end
  end

  describe "read operations" do
    describe "#user_state" do
      it "fetches account state from Hyperliquid" do
        allow(mock_info).to receive(:user_state).with(test_address).and_return({
          "assetPositions" => [],
          "crossMarginSummary" => { "accountValue" => "10000" }
        })

        result = client.user_state(test_address)

        expect(result).to be_a(Hash)
        expect(result).to have_key("assetPositions")
        expect(result).to have_key("crossMarginSummary")
      end

      it "handles invalid address gracefully" do
        allow(mock_info).to receive(:user_state).with("invalid").and_return({})

        result = client.user_state("invalid")

        expect(result).to be_a(Hash)
      end
    end

    describe "#open_orders" do
      it "fetches open orders for address" do
        allow(mock_info).to receive(:open_orders).with(test_address).and_return([])

        result = client.open_orders(test_address)

        expect(result).to be_an(Array)
      end
    end

    describe "#user_fills" do
      it "fetches recent fills for address" do
        allow(mock_info).to receive(:user_fills).with(test_address).and_return([])

        result = client.user_fills(test_address)

        expect(result).to be_an(Array)
      end
    end

    describe "#meta" do
      it "fetches asset metadata" do
        allow(mock_info).to receive(:meta).and_return({
          "universe" => [ { "name" => "BTC" } ]
        })

        result = client.meta

        expect(result).to be_a(Hash)
        expect(result).to have_key("universe")
      end
    end

    describe "#all_mids" do
      it "fetches current mid prices" do
        allow(mock_info).to receive(:all_mids).and_return({ "BTC" => "100000" })

        result = client.all_mids

        expect(result).to be_a(Hash)
      end
    end
  end

  describe "write operations" do
    let(:order_params) do
      {
        symbol: "BTC",
        side: "buy",
        size: 0.01,
        leverage: 3
      }
    end

    let(:successful_order_response) do
      {
        "status" => "ok",
        "response" => {
          "type" => "order",
          "data" => {
            "statuses" => [
              { "filled" => { "oid" => 12345, "avgPx" => "95000.50" } }
            ]
          }
        }
      }
    end

    describe "#place_order" do
      context "when configured with private key" do
        before do
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_PRIVATE_KEY", nil).and_return(test_private_key)
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(test_address)
          allow(mock_exchange).to receive(:address).and_return(test_address)
        end

        it "places a market order via exchange" do
          allow(mock_exchange).to receive(:market_order).and_return(successful_order_response)

          result = client.place_order(order_params)

          expect(mock_exchange).to have_received(:market_order).with(
            coin: "BTC",
            is_buy: true,
            size: "0.01",
            slippage: 0.005
          )
          expect(result["status"]).to eq("ok")
        end

        it "places a sell order when side is sell" do
          allow(mock_exchange).to receive(:market_order).and_return(successful_order_response)

          client.place_order(order_params.merge(side: "sell"))

          expect(mock_exchange).to have_received(:market_order).with(
            coin: "BTC",
            is_buy: false,
            size: "0.01",
            slippage: 0.005
          )
        end

        it "raises HyperliquidApiError on API failure" do
          allow(mock_exchange).to receive(:market_order)
            .and_raise(Hyperliquid::Error.new("Insufficient margin"))

          expect { client.place_order(order_params) }
            .to raise_error(
              Execution::HyperliquidClient::HyperliquidApiError,
              /Order placement failed/
            )
        end
      end

      context "when not configured" do
        before do
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_PRIVATE_KEY", nil).and_return(nil)
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(nil)
          allow(mock_sdk).to receive(:exchange).and_return(nil)
        end

        it "raises ConfigurationError for missing private key" do
          expect { client.place_order(order_params) }
            .to raise_error(
              Execution::HyperliquidClient::ConfigurationError,
              /HYPERLIQUID_PRIVATE_KEY not configured/
            )
        end
      end
    end

    describe "#cancel_order" do
      context "when configured" do
        before do
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_PRIVATE_KEY", nil).and_return(test_private_key)
          allow(ENV).to receive(:fetch).with("HYPERLIQUID_ADDRESS", nil).and_return(test_address)
          allow(mock_exchange).to receive(:address).and_return(test_address)
        end

        it "cancels order by ID" do
          cancel_response = { "status" => "ok", "response" => { "type" => "cancel" } }
          allow(mock_exchange).to receive(:cancel).and_return(cancel_response)

          result = client.cancel_order("BTC", 12345)

          expect(mock_exchange).to have_received(:cancel).with(coin: "BTC", oid: 12345)
          expect(result["status"]).to eq("ok")
        end

        it "raises HyperliquidApiError on cancel failure" do
          allow(mock_exchange).to receive(:cancel)
            .and_raise(Hyperliquid::Error.new("Order not found"))

          expect { client.cancel_order("BTC", 99999) }
            .to raise_error(
              Execution::HyperliquidClient::HyperliquidApiError,
              /Order cancellation failed/
            )
        end
      end
    end

    describe "#update_leverage" do
      it "returns informational response (leverage managed at account level)" do
        result = client.update_leverage("BTC", 10)

        expect(result[:status]).to eq("info")
        expect(result[:message]).to include("account level")
      end
    end
  end

  describe "#asset_index" do
    it "returns asset index for known symbols" do
      expect(client.asset_index("BTC")).to eq(0)
      expect(client.asset_index("ETH")).to eq(1)
    end

    it "raises error for unknown symbols" do
      expect { client.asset_index("UNKNOWN") }
        .to raise_error(Execution::HyperliquidClient::UnknownAssetError)
    end
  end

  describe "error handling" do
    it "wraps API errors in HyperliquidApiError" do
      allow(mock_info).to receive(:user_state)
        .and_raise(Faraday::TimeoutError)

      expect { client.user_state(test_address) }
        .to raise_error(Execution::HyperliquidClient::HyperliquidApiError)
    end
  end
end
