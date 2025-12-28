# frozen_string_literal: true

# Market snapshot job - continuous data collection
#
# Runs every minute to:
# 1. Fetch current prices for all tracked assets
# 2. Calculate technical indicators
# 3. Fetch sentiment data
# 4. Store snapshot in database for historical analysis
# 5. Broadcast updates via ActionCable for real-time dashboard
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
    snapshots = []

    assets.each do |asset|
      snapshot = create_snapshot(
        asset: asset,
        price_fetcher: price_fetcher,
        indicator_calculator: indicator_calculator,
        sentiment: sentiment,
        captured_at: captured_at
      )
      snapshots << snapshot if snapshot
    rescue StandardError => e
      Rails.logger.error "[MarketSnapshot] Error for #{asset}: #{e.message}"
    end

    # Broadcast to WebSocket subscribers
    broadcast_updates(snapshots) if snapshots.any?

    Rails.logger.info "[MarketSnapshot] Snapshot complete for #{assets.size} assets"
  end

  private

  # Create a market snapshot for a single asset
  #
  # Fetches current price, calculates technical indicators, and persists to database.
  #
  # @param asset [String] Asset symbol (e.g., "BTC")
  # @param price_fetcher [DataIngestion::PriceFetcher] Price data fetcher
  # @param indicator_calculator [Indicators::Calculator] Technical indicator calculator
  # @param sentiment [Hash] Sentiment data to attach to snapshot
  # @param captured_at [Time] Timestamp for the snapshot
  # @return [MarketSnapshot, nil] Created snapshot or nil on failure
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
    snapshot = MarketSnapshot.create!(
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
    snapshot
  end

  # Broadcast snapshot updates via WebSocket channels
  #
  # Sends updates to both MarketsChannel (per-symbol) and DashboardChannel (aggregated).
  #
  # @param snapshots [Array<MarketSnapshot>] Snapshots to broadcast
  # @return [void]
  def broadcast_updates(snapshots)
    # Broadcast via MarketsChannel for price updates
    MarketsChannel.broadcast_snapshots(snapshots)

    # Also broadcast market summary via DashboardChannel
    market_data = snapshots.to_h do |s|
      indicators = s.indicators || {}
      [
        s.symbol,
        {
          price: s.price.to_f,
          rsi: indicators["rsi_14"]&.round(1),
          rsi_signal: s.rsi_signal,
          macd_signal: s.macd_signal,
          updated_at: s.captured_at.iso8601
        }
      ]
    end

    DashboardChannel.broadcast_market_update(market_data)
  rescue StandardError => e
    Rails.logger.error "[MarketSnapshot] Broadcast error: #{e.message}"
  end
end
