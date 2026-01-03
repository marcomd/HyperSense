# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarketSnapshotJob, type: :job do
  let(:price_fetcher) { instance_double(DataIngestion::PriceFetcher) }
  let(:sentiment_fetcher) { instance_double(DataIngestion::SentimentFetcher) }
  let(:indicator_calculator) { instance_double(Indicators::Calculator) }

  let(:ticker_data) do
    {
      price: 97000.0,
      high_24h: 98000.0,
      low_24h: 96000.0,
      volume_24h: 1234.5,
      price_change_pct_24h: 2.5
    }
  end

  let(:sentiment_data) do
    {
      fear_greed: { value: 65, classification: "Greed" },
      fetched_at: Time.current
    }
  end

  let(:indicators) do
    {
      ema_20: 96500.0,
      ema_50: 95000.0,
      ema_100: 94000.0,
      rsi_14: 55.0,
      macd: { macd: 100.0, signal: 90.0, histogram: 10.0 },
      pivot_points: { pp: 97000.0, r1: 98000.0, s1: 96000.0 },
      atr_14: 1500.0
    }
  end

  let(:candles) do
    (1..150).map { |i| { open: 97000.0 - i, high: 98000.0 - i, low: 96000.0 - i, close: 97000.0 } }
  end

  before do
    allow(DataIngestion::PriceFetcher).to receive(:new).and_return(price_fetcher)
    allow(DataIngestion::SentimentFetcher).to receive(:new).and_return(sentiment_fetcher)
    allow(Indicators::Calculator).to receive(:new).and_return(indicator_calculator)

    allow(price_fetcher).to receive(:fetch_ticker).and_return(ticker_data)
    allow(price_fetcher).to receive(:fetch_klines).and_return(candles)
    allow(sentiment_fetcher).to receive(:fetch_all).and_return(sentiment_data)
    allow(indicator_calculator).to receive(:calculate_all).and_return(indicators)

    allow(MarketsChannel).to receive(:broadcast_snapshots)
    allow(DashboardChannel).to receive(:broadcast_market_update)
  end

  describe "#perform" do
    it "fetches sentiment data once for all assets" do
      expect(sentiment_fetcher).to receive(:fetch_all).once

      described_class.new.perform
    end

    it "creates market snapshots for each configured asset" do
      expect { described_class.new.perform }.to change(MarketSnapshot, :count).by(Settings.assets.count)
    end

    it "fetches ticker data for each asset" do
      Settings.assets.each do |asset|
        expect(price_fetcher).to receive(:fetch_ticker).with(asset)
      end

      described_class.new.perform
    end

    it "calculates indicators for each asset" do
      expect(indicator_calculator).to receive(:calculate_all).exactly(Settings.assets.count).times

      described_class.new.perform
    end

    it "passes candles to calculate_all for ATR calculation" do
      expect(indicator_calculator).to receive(:calculate_all).with(
        array_including(97000.0),
        hash_including(candles: candles)
      ).at_least(:once)

      described_class.new.perform
    end

    it "broadcasts snapshots via MarketsChannel" do
      expect(MarketsChannel).to receive(:broadcast_snapshots)

      described_class.new.perform
    end

    it "broadcasts market update via DashboardChannel" do
      expect(DashboardChannel).to receive(:broadcast_market_update)

      described_class.new.perform
    end

    context "when fetching fails for one asset" do
      before do
        call_count = 0
        allow(price_fetcher).to receive(:fetch_ticker) do |asset|
          call_count += 1
          raise StandardError, "API error" if call_count == 1

          ticker_data
        end
      end

      it "continues processing other assets" do
        # Should still create snapshots for remaining assets
        expect { described_class.new.perform }.to change(MarketSnapshot, :count).by(Settings.assets.count - 1)
      end

      it "logs the error" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:error).with(/Error for/)

        described_class.new.perform
      end
    end

    context "when broadcast fails" do
      before do
        allow(MarketsChannel).to receive(:broadcast_snapshots).and_raise(StandardError, "Broadcast error")
      end

      it "logs the error but does not fail" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:error).with(/Broadcast error/)

        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "is queued in the data queue" do
      expect(described_class.queue_name).to eq("data")
    end
  end
end
