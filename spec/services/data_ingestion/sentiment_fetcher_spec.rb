# frozen_string_literal: true

require "spec_helper"
require "faraday"
require_relative "../../../app/services/data_ingestion/sentiment_fetcher"

RSpec.describe DataIngestion::SentimentFetcher do
  subject(:fetcher) { described_class.new }

  describe "#fetch_fear_greed", :vcr do
    it "fetches Fear & Greed Index data" do
      result = fetcher.fetch_fear_greed

      expect(result[:value]).to be_between(0, 100)
      expect(result[:classification]).to be_a(String)
      expect(result[:timestamp]).to be_a(Time)
    end
  end

  describe "#interpret_sentiment" do
    it "identifies extreme fear as contrarian bullish" do
      result = fetcher.interpret_sentiment(10)

      expect(result[:level]).to eq(:extreme_fear)
      expect(result[:bias]).to eq(:contrarian_bullish)
      expect(result[:strength]).to eq(1.0)
    end

    it "identifies fear as slightly bullish" do
      result = fetcher.interpret_sentiment(30)

      expect(result[:level]).to eq(:fear)
      expect(result[:bias]).to eq(:slightly_bullish)
    end

    it "identifies neutral sentiment" do
      result = fetcher.interpret_sentiment(50)

      expect(result[:level]).to eq(:neutral)
      expect(result[:bias]).to eq(:neutral)
      expect(result[:strength]).to eq(0.0)
    end

    it "identifies greed as slightly bearish" do
      result = fetcher.interpret_sentiment(70)

      expect(result[:level]).to eq(:greed)
      expect(result[:bias]).to eq(:slightly_bearish)
    end

    it "identifies extreme greed as contrarian bearish" do
      result = fetcher.interpret_sentiment(90)

      expect(result[:level]).to eq(:extreme_greed)
      expect(result[:bias]).to eq(:contrarian_bearish)
      expect(result[:strength]).to eq(1.0)
    end
  end
end
