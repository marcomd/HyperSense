# frozen_string_literal: true

module DataIngestion
  # Fetches current price data from Binance API
  #
  # Uses Binance public API (no authentication required):
  # - /api/v3/ticker/24hr - 24h price statistics
  # - /api/v3/klines - Historical candlestick data
  #
  class PriceFetcher
    BINANCE_API_URL = "https://api.binance.com"

    # Map our symbols to Binance trading pairs
    SYMBOL_MAP = {
      "BTC" => "BTCUSDT",
      "ETH" => "ETHUSDT",
      "SOL" => "SOLUSDT",
      "BNB" => "BNBUSDT"
    }.freeze

    def initialize
      @conn = Faraday.new(url: BINANCE_API_URL) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end

    # Fetch current prices and 24h stats for all configured assets
    #
    # @return [Hash] Asset prices and stats
    #   { "BTC" => { price: 97000.0, volume_24h: 1234.5, ... }, ... }
    #
    def fetch_all
      assets = Settings.assets || SYMBOL_MAP.keys
      results = {}

      assets.each do |asset|
        results[asset] = fetch_ticker(asset)
      rescue StandardError => e
        Rails.logger.error "[PriceFetcher] Error fetching #{asset}: #{e.message}"
        results[asset] = { error: e.message }
      end

      results
    end

    # Fetch 24h ticker data for a single asset
    #
    # @param asset [String] Asset symbol (e.g., "BTC")
    # @return [Hash] Ticker data
    #
    def fetch_ticker(asset)
      symbol = SYMBOL_MAP[asset] || "#{asset}USDT"
      response = @conn.get("/api/v3/ticker/24hr", { symbol: symbol })

      raise "API Error: #{response.status}" unless response.success?

      data = response.body
      {
        symbol: asset,
        price: data["lastPrice"].to_f,
        price_change_24h: data["priceChange"].to_f,
        price_change_pct_24h: data["priceChangePercent"].to_f,
        high_24h: data["highPrice"].to_f,
        low_24h: data["lowPrice"].to_f,
        volume_24h: data["volume"].to_f,
        quote_volume_24h: data["quoteVolume"].to_f,
        open_24h: data["openPrice"].to_f,
        fetched_at: Time.current
      }
    end

    # Fetch historical klines (candlestick) data
    #
    # @param asset [String] Asset symbol
    # @param interval [String] Kline interval (1m, 5m, 15m, 1h, 4h, 1d)
    # @param limit [Integer] Number of candles to fetch (max 1000)
    # @return [Array<Hash>] Array of OHLCV candles
    #
    def fetch_klines(asset, interval: "1h", limit: 100)
      symbol = SYMBOL_MAP[asset] || "#{asset}USDT"
      response = @conn.get("/api/v3/klines", { symbol:, interval:, limit: })

      raise "API Error: #{response.status}" unless response.success?

      response.body.map do |candle|
        {
          open_time: Time.at(candle[0] / 1000),
          open: candle[1].to_f,
          high: candle[2].to_f,
          low: candle[3].to_f,
          close: candle[4].to_f,
          volume: candle[5].to_f,
          close_time: Time.at(candle[6] / 1000)
        }
      end
    end

    # Fetch prices suitable for indicator calculation
    #
    # @param asset [String] Asset symbol
    # @param interval [String] Kline interval
    # @param limit [Integer] Number of candles
    # @return [Array<Float>] Array of closing prices (oldest first)
    #
    def fetch_prices_for_indicators(asset, interval: "1h", limit: 150)
      klines = fetch_klines(asset, interval:, limit:)
      klines.map { |k| k[:close] }
    end
  end
end
