# frozen_string_literal: true

# Market snapshot job - continuous data collection
#
# Runs every minute to:
# 1. Fetch current prices for all tracked assets
# 2. Calculate technical indicators
# 3. Fetch sentiment data
# 4. Store snapshot in database for historical analysis
#
class MarketSnapshotJob < ApplicationJob
  queue_as :data

  def perform
    Rails.logger.info "[MarketSnapshot] Capturing market snapshot..."

    captured_at = Time.current
    price_fetcher = DataIngestion::PriceFetcher.new
    indicator_calculator = Indicators::Calculator.new
    sentiment_fetcher = DataIngestion::SentimentFetcher.new

    # Fetch sentiment (once for all assets)
    sentiment = sentiment_fetcher.fetch_all

    # Fetch prices and create snapshots for each asset
    assets = Settings.assets || %w[BTC ETH SOL BNB]

    assets.each do |asset|
      create_snapshot(
        asset: asset,
        price_fetcher: price_fetcher,
        indicator_calculator: indicator_calculator,
        sentiment: sentiment,
        captured_at: captured_at
      )
    rescue StandardError => e
      Rails.logger.error "[MarketSnapshot] Error for #{asset}: #{e.message}"
    end

    Rails.logger.info "[MarketSnapshot] Snapshot complete for #{assets.size} assets"
  end

  private

  def create_snapshot(asset:, price_fetcher:, indicator_calculator:, sentiment:, captured_at:)
    # Fetch current ticker data
    ticker = price_fetcher.fetch_ticker(asset)

    # Fetch historical prices for indicators
    prices = price_fetcher.fetch_prices_for_indicators(asset, interval: "1h", limit: 150)

    # Calculate indicators
    indicators = indicator_calculator.calculate_all(
      prices,
      high: ticker[:high_24h],
      low: ticker[:low_24h]
    )

    # Create snapshot
    MarketSnapshot.create!(
      symbol: asset,
      price: ticker[:price],
      high_24h: ticker[:high_24h],
      low_24h: ticker[:low_24h],
      volume_24h: ticker[:volume_24h],
      price_change_pct_24h: ticker[:price_change_pct_24h],
      indicators: indicators,
      sentiment: sentiment,
      captured_at: captured_at
    )

    Rails.logger.info "[MarketSnapshot] #{asset}: $#{ticker[:price]} | RSI: #{indicators[:rsi_14]&.round(1)}"
  end
end
