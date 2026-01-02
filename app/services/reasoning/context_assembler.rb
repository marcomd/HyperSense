# frozen_string_literal: true

module Reasoning
  # Assembles market context for LLM reasoning
  #
  # Gathers data from:
  # - MarketSnapshot (current prices, indicators)
  # - Sentiment data (Fear & Greed)
  # - MacroStrategy (if available)
  # - Historical data for trend analysis
  #
  class ContextAssembler
    LOOKBACK_HOURS = 24
    LOOKBACK_DAYS_MACRO = 7
    PRICE_ACTION_CANDLES_LIMIT = 24

    # @param symbol [String, nil] Asset symbol for single-asset context
    def initialize(symbol: nil)
      @symbol = symbol
      @position_manager = Execution::PositionManager.new
    end

    # Assemble context for low-level agent (trade decisions)
    # @param macro_strategy [MacroStrategy, nil] Current macro strategy
    # @return [Hash] Structured context for LLM
    def for_trading(macro_strategy: nil)
      {
        timestamp: Time.current.iso8601,
        symbol: @symbol,
        weights: context_weights,
        # Position awareness
        current_position: current_position_for(@symbol),
        # Weighted data sources
        forecast: forecast_for(@symbol),
        news: recent_news,
        whale_alerts: recent_whale_alerts,
        # Existing data
        market_data: market_data_for(@symbol),
        technical_indicators: technical_indicators_for(@symbol),
        sentiment: current_sentiment,
        macro_context: macro_context(macro_strategy),
        recent_price_action: recent_price_action(@symbol),
        risk_parameters: risk_parameters
      }
    end

    # Assemble context for high-level agent (macro strategy)
    # @return [Hash] Structured context for LLM
    def for_macro_analysis
      {
        timestamp: Time.current.iso8601,
        weights: context_weights,
        # Weighted data sources
        forecasts: forecasts_for_all_assets,
        news: recent_news,
        whale_alerts: recent_whale_alerts,
        # Existing data
        assets_overview: assets_overview,
        market_sentiment: current_sentiment,
        historical_trends: historical_trends,
        risk_parameters: risk_parameters
      }
    end

    # Get configured context weights
    # @return [Hash] Weight configuration
    def context_weights
      {
        forecast: Settings.weights.forecast,
        sentiment: Settings.weights.sentiment,
        technical: Settings.weights.technical,
        whale_alerts: Settings.weights.whale_alerts
      }
    end

    # Get forecast data for a symbol from Prophet predictions
    # @param symbol [String] Asset symbol
    # @return [Hash, nil] Forecast data by timeframe or nil if not available
    def forecast_for(symbol)
      forecasts = Forecast.latest_all_timeframes_for(symbol)
      return nil if forecasts.empty?

      forecasts
    end

    # Get forecasts for all configured assets
    # @return [Hash, nil] Forecasts by symbol or nil
    def forecasts_for_all_assets
      result = Settings.assets.to_a.to_h do |symbol|
        forecasts = forecast_for(symbol)
        next [ symbol, nil ] unless forecasts

        # Extract the 1h forecast for macro context (most relevant timeframe)
        forecast_1h = forecasts["1h"]
        [
          symbol,
          {
            current_price: forecast_1h&.dig(:current_price),
            predicted_1h: forecast_1h&.dig(:predicted_price),
            direction: forecast_1h&.dig(:direction)
          }
        ]
      end.compact

      result.empty? ? nil : result
    end

    # Get recent news items from RSS fetcher
    # @return [Array, nil] Array of news items or nil if not available
    def recent_news
      fetcher = DataIngestion::NewsFetcher.new
      news = fetcher.recent_news(limit: 5)
      news.presence
    rescue StandardError => e
      Rails.logger.warn "[ContextAssembler] Failed to fetch news: #{e.message}"
      nil
    end

    # Get recent whale alerts from whale-alert.io
    # @return [Array, nil] Array of whale alerts or nil if not available
    def recent_whale_alerts
      fetcher = DataIngestion::WhaleAlertFetcher.new
      alerts = fetcher.recent_alerts(limit: 5)
      alerts.presence
    rescue StandardError => e
      Rails.logger.warn "[ContextAssembler] Failed to fetch whale alerts: #{e.message}"
      nil
    end

    private

    # Get market data for a specific symbol
    # @param symbol [String] Asset symbol
    # @return [Hash] Market data hash
    def market_data_for(symbol)
      snapshot = MarketSnapshot.latest_for(symbol)
      return {} unless snapshot

      {
        price: snapshot.price.to_f,
        high_24h: snapshot.high_24h.to_f,
        low_24h: snapshot.low_24h.to_f,
        volume_24h: snapshot.volume_24h.to_f,
        price_change_pct_24h: snapshot.price_change_pct_24h.to_f,
        captured_at: snapshot.captured_at.iso8601
      }
    end

    # Get technical indicators for a specific symbol
    # @param symbol [String] Asset symbol
    # @return [Hash] Technical indicators hash
    def technical_indicators_for(symbol)
      snapshot = MarketSnapshot.latest_for(symbol)
      return {} unless snapshot

      indicators = snapshot.indicators || {}
      {
        ema_20: indicators["ema_20"],
        ema_50: indicators["ema_50"],
        ema_100: indicators["ema_100"],
        ema_200: indicators["ema_200"],
        rsi_14: indicators["rsi_14"],
        atr_14: indicators["atr_14"],
        macd: indicators["macd"],
        pivot_points: indicators["pivot_points"],
        signals: {
          rsi: snapshot.rsi_signal,
          macd: snapshot.macd_signal,
          atr: snapshot.atr_signal,
          above_ema_20: snapshot.above_ema?(20),
          above_ema_50: snapshot.above_ema?(50),
          above_ema_200: snapshot.above_ema?(200)
        }
      }
    end

    # Get current market sentiment
    # @return [Hash] Sentiment data hash
    def current_sentiment
      snapshot = MarketSnapshot.recent.first
      return {} unless snapshot&.sentiment

      fear_greed = snapshot.sentiment.dig("fear_greed") || {}
      {
        fear_greed_value: fear_greed["value"],
        fear_greed_classification: fear_greed["classification"],
        fetched_at: snapshot.sentiment["fetched_at"]
      }
    end

    # Get macro strategy context
    # @param strategy [MacroStrategy, nil] Current macro strategy
    # @return [Hash] Macro context hash
    def macro_context(strategy)
      return { available: false } unless strategy&.valid_until&.> Time.current

      {
        available: true,
        market_narrative: strategy.market_narrative,
        bias: strategy.bias,
        risk_tolerance: strategy.risk_tolerance.to_f,
        key_levels: strategy.key_levels,
        valid_until: strategy.valid_until.iso8601
      }
    end

    # Get recent price action for trend analysis
    # @param symbol [String] Asset symbol
    # @return [Hash] Recent price action data
    def recent_price_action(symbol)
      snapshots = MarketSnapshot.for_symbol(symbol)
                                .last_hours(LOOKBACK_HOURS)
                                .recent
                                .limit(PRICE_ACTION_CANDLES_LIMIT)

      return {} if snapshots.empty?

      prices = snapshots.map { |s| s.price.to_f }
      {
        prices_last_24h: prices.reverse,
        high: prices.max,
        low: prices.min,
        trend: calculate_trend(prices)
      }
    end

    # Calculate trend from price array
    # @param prices [Array<Float>] Prices array (newest first)
    # @return [String] Trend classification
    def calculate_trend(prices)
      return "neutral" if prices.size < 2

      # Calculate percentage change from oldest to newest
      oldest = prices.last
      newest = prices.first
      return "neutral" if oldest.zero?

      change = (newest - oldest) / oldest * 100
      case change
      when ..(-3) then "strong_downtrend"
      when -3..(-1) then "downtrend"
      when -1..1 then "neutral"
      when 1..3 then "uptrend"
      else "strong_uptrend"
      end
    end

    # Get overview of all configured assets
    # @return [Array<Hash>] Array of asset overview hashes
    def assets_overview
      Settings.assets.to_a.map do |asset|
        {
          symbol: asset,
          market_data: market_data_for(asset),
          technical_indicators: technical_indicators_for(asset)
        }
      end
    end

    # Get historical trends for all assets
    # @return [Hash] Historical trends by symbol
    def historical_trends
      Settings.assets.to_a.to_h do |asset|
        snapshots = MarketSnapshot.for_symbol(asset)
                                  .last_days(LOOKBACK_DAYS_MACRO)
                                  .recent

        prices = snapshots.pluck(:price).map(&:to_f)
        [ asset, calculate_historical_trend(prices) ]
      end
    end

    # Calculate historical trend data
    # @param prices [Array<Float>] Price history
    # @return [Hash] Trend data
    def calculate_historical_trend(prices)
      return { price_start: 0, price_end: 0, change_pct: 0, volatility: 0 } if prices.empty?

      {
        price_start: prices.last,
        price_end: prices.first,
        change_pct: calculate_change_pct(prices),
        volatility: calculate_volatility(prices)
      }
    end

    # Calculate percentage change
    # @param prices [Array<Float>] Price history (newest first)
    # @return [Float] Percentage change
    def calculate_change_pct(prices)
      return 0 if prices.size < 2 || prices.last.zero?

      ((prices.first - prices.last) / prices.last * 100).round(2)
    end

    # Calculate volatility (coefficient of variation)
    # @param prices [Array<Float>] Price history
    # @return [Float] Volatility percentage
    def calculate_volatility(prices)
      return 0 if prices.size < 2

      mean = prices.sum / prices.size
      return 0 if mean.zero?

      variance = prices.sum { |p| (p - mean)**2 } / prices.size
      (Math.sqrt(variance) / mean * 100).round(2)
    end

    # Get risk parameters from settings
    # @return [Hash] Risk parameters
    def risk_parameters
      {
        max_position_size: Settings.risk.max_position_size,
        min_confidence: Settings.risk.min_confidence,
        max_leverage: Settings.risk.max_leverage,
        default_leverage: Settings.risk.default_leverage,
        max_open_positions: Settings.risk.max_open_positions
      }
    end

    # Get current position information for a symbol
    # @param symbol [String] Asset symbol
    # @return [Hash] Position data or indication of no position
    def current_position_for(symbol)
      position = @position_manager.get_open_position(symbol)
      return { has_position: false } unless position

      {
        has_position: true,
        direction: position.direction,
        size: position.size.to_f,
        entry_price: position.entry_price.to_f,
        current_price: position.current_price.to_f,
        unrealized_pnl: position.unrealized_pnl.to_f,
        pnl_percent: position.pnl_percent,
        leverage: position.leverage,
        stop_loss_price: position.stop_loss_price&.to_f,
        take_profit_price: position.take_profit_price&.to_f,
        opened_at: position.opened_at&.iso8601
      }
    end
  end
end
