# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::HyperliquidClient do
  let(:client) { described_class.new }
  let(:test_address) { "0x1234567890abcdef1234567890abcdef12345678" }
  let(:mock_sdk) { instance_double(Hyperliquid::SDK) }
  let(:mock_info) { instance_double(Hyperliquid::Info) }

  before do
    allow(Hyperliquid::SDK).to receive(:new).and_return(mock_sdk)
    allow(mock_sdk).to receive(:info).and_return(mock_info)
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
    describe "#place_order" do
      it "raises NotImplementedError with guidance" do
        expect { client.place_order({}) }
          .to raise_error(Execution::HyperliquidClient::WriteOperationNotImplemented)
      end
    end

    describe "#cancel_order" do
      it "raises NotImplementedError with guidance" do
        expect { client.cancel_order("BTC", 123) }
          .to raise_error(Execution::HyperliquidClient::WriteOperationNotImplemented)
      end
    end

    describe "#update_leverage" do
      it "raises NotImplementedError with guidance" do
        expect { client.update_leverage("BTC", 10) }
          .to raise_error(Execution::HyperliquidClient::WriteOperationNotImplemented)
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
