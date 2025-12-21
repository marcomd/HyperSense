# frozen_string_literal: true

# Market snapshot job - continuous data collection
#
# Runs every minute to:
# 1. Fetch current prices for all tracked assets
# 2. Calculate technical indicators
# 3. Store snapshot in database for historical analysis
#
class MarketSnapshotJob < ApplicationJob
  queue_as :data

  def perform
    Rails.logger.info "[MarketSnapshot] Capturing market snapshot..."

    # TODO: Implement data pipeline
    # fetcher = DataIngestion::PriceFetcher.new
    # prices = fetcher.fetch_all
    #
    # calculator = Indicators::Calculator.new
    # indicators = calculator.calculate_all(prices)
    #
    # MarketSnapshot.create!(
    #   prices: prices,
    #   indicators: indicators,
    #   captured_at: Time.current
    # )

    Rails.logger.info "[MarketSnapshot] Snapshot captured"
  end
end
