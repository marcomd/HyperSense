# frozen_string_literal: true

module Api
  module V1
    # Aggregated dashboard data for the frontend
    class DashboardController < BaseController
      # Display limits for dashboard components
      RECENT_POSITIONS_LIMIT = 10
      RECENT_DECISIONS_LIMIT = 5

      # Health check thresholds (minutes)
      MARKET_DATA_HEALTH_MINUTES = 5
      TRADING_CYCLE_HEALTH_MINUTES = 15

      # GET /api/v1/dashboard
      # Returns all data needed for the main dashboard view
      def index
        render json: {
          account: account_summary,
          positions: open_positions,
          market: market_overview,
          macro_strategy: current_macro_strategy,
          recent_decisions: recent_decisions,
          system_status: system_status,
          cost_summary: cost_summary
        }
      end

      # GET /api/v1/dashboard/account
      # Returns account summary
      def account
        render json: { account: account_summary }
      end

      # GET /api/v1/dashboard/system_status
      # Returns system health and job status
      def system_status_endpoint
        render json: { system: system_status }
      end

      private

      # Build account summary data for dashboard display
      #
      # Aggregates open positions, realized PnL, and circuit breaker status.
      #
      # @return [Hash] Account summary with keys :open_positions_count, :total_unrealized_pnl,
      #   :total_margin_used, :realized_pnl_today, :paper_trading, :circuit_breaker
      def account_summary
        open_positions = Position.open

        # Calculate realized PnL from closed positions today
        today_start = Time.current.beginning_of_day
        realized_today = Position.closed
                                 .where("closed_at >= ?", today_start)
                                 .sum(:realized_pnl)

        # Get circuit breaker status
        circuit_breaker = Risk::CircuitBreaker.new if defined?(Risk::CircuitBreaker)
        breaker_status = circuit_breaker&.status || { trading_allowed: true }

        {
          open_positions_count: open_positions.count,
          total_unrealized_pnl: open_positions.sum(:unrealized_pnl).to_f.round(2),
          total_margin_used: open_positions.sum(:margin_used).to_f.round(2),
          realized_pnl_today: realized_today.to_f.round(2),
          paper_trading: Settings.trading.paper_trading,
          circuit_breaker: {
            trading_allowed: breaker_status[:trading_allowed],
            daily_loss: breaker_status[:daily_loss]&.round(2),
            consecutive_losses: breaker_status[:consecutive_losses]
          }
        }
      end

      # Fetch and serialize open positions for dashboard display
      #
      # Returns the 10 most recent open positions with key trading data.
      #
      # @return [Array<Hash>] Array of position hashes with trading data
      def open_positions
        Position.open.recent.limit(RECENT_POSITIONS_LIMIT).map do |p|
          {
            id: p.id,
            symbol: p.symbol,
            direction: p.direction,
            size: p.size.to_f,
            entry_price: p.entry_price.to_f,
            current_price: p.current_price&.to_f,
            unrealized_pnl: p.unrealized_pnl&.to_f,
            pnl_percent: p.pnl_percent,
            leverage: p.leverage,
            stop_loss_price: p.stop_loss_price&.to_f,
            take_profit_price: p.take_profit_price&.to_f
          }
        end
      end

      # Build market overview with prices, indicators, and forecasts for all assets
      #
      # Uses batch loading to avoid N+1 queries when fetching snapshots and forecasts.
      #
      # @return [Hash] Market data keyed by symbol (e.g., { "BTC" => { price: 97000, ... } })
      def market_overview
        # Batch load latest snapshots for all symbols (single query)
        snapshots_by_symbol = MarketSnapshot.latest_per_symbol
                                            .index_by(&:symbol)

        # Batch load latest 1h forecasts for all symbols (single query)
        # Note: PostgreSQL DISTINCT ON requires ORDER BY to start with the DISTINCT ON column
        forecasts_by_symbol = Forecast.where(symbol: Settings.assets.to_a, timeframe: "1h")
                                      .select("DISTINCT ON (symbol) *")
                                      .order(:symbol, created_at: :desc)
                                      .index_by(&:symbol)

        Settings.assets.to_h do |symbol|
          snapshot = snapshots_by_symbol[symbol]
          next [ symbol, nil ] unless snapshot

          indicators = snapshot.indicators || {}
          forecast = forecasts_by_symbol[symbol]

          [
            symbol,
            {
              price: snapshot.price.to_f,
              rsi: indicators["rsi_14"]&.round(1),
              rsi_signal: snapshot.rsi_signal,
              macd_signal: snapshot.macd_signal,
              above_ema_50: snapshot.above_ema?(50),
              forecast_direction: forecast&.direction,
              forecast_change_pct: forecast&.predicted_change_pct,
              updated_at: snapshot.captured_at.iso8601
            }
          ]
        end
      end

      # Serialize the currently active macro strategy
      #
      # Returns the active strategy with bias, risk tolerance, and validity info.
      #
      # @return [Hash, nil] Macro strategy data or nil if no active strategy
      def current_macro_strategy
        strategy = MacroStrategy.active
        return nil unless strategy

        {
          id: strategy.id,
          bias: strategy.bias,
          risk_tolerance: strategy.risk_tolerance.to_f,
          market_narrative: strategy.market_narrative,
          key_levels: strategy.key_levels,
          llm_model: strategy.llm_model,
          valid_until: strategy.valid_until.iso8601,
          created_at: strategy.created_at.iso8601,
          stale: strategy.stale?
        }
      end

      # Fetch and serialize recent trading decisions
      #
      # Returns the 5 most recent trading decisions with key data.
      #
      # @return [Array<Hash>] Array of decision hashes
      def recent_decisions
        TradingDecision.recent.limit(RECENT_DECISIONS_LIMIT).map do |d|
          {
            id: d.id,
            symbol: d.symbol,
            operation: d.operation,
            direction: d.direction,
            confidence: d.confidence&.to_f,
            status: d.status,
            reasoning: d.reasoning,
            llm_model: d.llm_model,
            created_at: d.created_at.iso8601
          }
        end
      end

      # Build system health status for monitoring
      #
      # Checks health of market data collection, trading cycle, and macro strategy.
      # A component is considered healthy if its last update is within expected intervals.
      #
      # @return [Hash] System status with health indicators for each component
      def system_status
        # Check last market snapshot
        last_snapshot = MarketSnapshot.recent.first
        last_decision = TradingDecision.recent.first
        last_macro = MacroStrategy.recent.first

        {
          market_data: {
            healthy: last_snapshot && last_snapshot.captured_at > MARKET_DATA_HEALTH_MINUTES.minutes.ago,
            last_update: last_snapshot&.captured_at&.iso8601
          },
          trading_cycle: {
            healthy: last_decision && last_decision.created_at > TRADING_CYCLE_HEALTH_MINUTES.minutes.ago,
            last_run: last_decision&.created_at&.iso8601
          },
          macro_strategy: {
            healthy: last_macro && !last_macro.stale?,
            last_update: last_macro&.created_at&.iso8601,
            stale: last_macro&.stale?
          },
          paper_trading: Settings.trading.paper_trading,
          assets_tracked: Settings.assets.to_a
        }
      end

      # Build cost summary for dashboard display
      #
      # Calculates on-the-fly: trading fees, LLM costs, server costs.
      # Returns net P&L (gross minus trading fees) for the current day.
      #
      # @return [Hash] Cost breakdown for today with net P&L
      def cost_summary
        calculator = Costs::Calculator.new

        today_costs = calculator.summary(period: :today)
        net_pnl = calculator.net_pnl(period: :today)

        {
          period: "today",
          trading_fees: today_costs[:trading_fees][:total],
          llm_costs: today_costs[:llm_costs][:total],
          server_cost_daily: today_costs[:server_cost][:daily_rate],
          total_costs: today_costs[:total_costs],
          gross_realized_pnl: net_pnl[:gross_realized_pnl],
          net_realized_pnl: net_pnl[:net_realized_pnl],
          llm_provider: today_costs[:llm_costs][:provider],
          llm_model: today_costs[:llm_costs][:model]
        }
      end
    end
  end
end
