# frozen_string_literal: true

require "spec_helper"
require "faraday"
require_relative "../../../app/services/data_ingestion/price_fetcher"

RSpec.describe DataIngestion::PriceFetcher do
  subject(:fetcher) { described_class.new }

  describe "#fetch_ticker", :vcr do
    it "fetches BTC ticker data" do
      result = fetcher.fetch_ticker("BTC")

      expect(result[:symbol]).to eq("BTC")
      expect(result[:price]).to be_a(Float)
      expect(result[:price]).to be > 0
      expect(result[:volume_24h]).to be_a(Float)
      expect(result[:high_24h]).to be >= result[:low_24h]
    end

    it "handles unknown symbols gracefully" do
      expect { fetcher.fetch_ticker("UNKNOWN") }.to raise_error(RuntimeError)
    end
  end

  describe "#fetch_klines", :vcr do
    it "fetches historical candlestick data" do
      result = fetcher.fetch_klines("BTC", interval: "1h", limit: 10)

      expect(result).to be_an(Array)
      expect(result.size).to eq(10)

      candle = result.first
      expect(candle).to include(:open, :high, :low, :close, :volume)
      expect(candle[:high]).to be >= candle[:low]
    end
  end

  describe "#fetch_prices_for_indicators", :vcr do
    it "returns array of closing prices" do
      result = fetcher.fetch_prices_for_indicators("ETH", interval: "1h", limit: 50)

      expect(result).to be_an(Array)
      expect(result.size).to eq(50)
      expect(result).to all(be_a(Float))
    end
  end

  describe "SYMBOL_MAP" do
    it "maps common symbols to Binance pairs" do
      expect(described_class::SYMBOL_MAP["BTC"]).to eq("BTCUSDT")
      expect(described_class::SYMBOL_MAP["ETH"]).to eq("ETHUSDT")
      expect(described_class::SYMBOL_MAP["SOL"]).to eq("SOLUSDT")
      expect(described_class::SYMBOL_MAP["BNB"]).to eq("BNBUSDT")
    end
  end
end
