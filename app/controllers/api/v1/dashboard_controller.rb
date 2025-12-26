# frozen_string_literal: true

module Api
  module V1
    # Aggregated dashboard data for the frontend
    class DashboardController < BaseController
      # GET /api/v1/dashboard
      # Returns all data needed for the main dashboard view
      def index
        render json: {
          account: account_summary,
          positions: open_positions,
          market: market_overview,
          macro_strategy: current_macro_strategy,
          recent_decisions: recent_decisions,
          system_status: system_status
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

      def open_positions
        Position.open.recent.limit(10).map do |p|
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

      def market_overview
        Settings.assets.to_h do |symbol|
          snapshot = MarketSnapshot.latest_for(symbol)
          next [ symbol, nil ] unless snapshot

          indicators = snapshot.indicators || {}
          forecast = Forecast.latest_for(symbol, "1h")

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

      def current_macro_strategy
        strategy = MacroStrategy.active
        return nil unless strategy

        {
          id: strategy.id,
          bias: strategy.bias,
          risk_tolerance: strategy.risk_tolerance.to_f,
          market_narrative: strategy.market_narrative,
          key_levels: strategy.key_levels,
          valid_until: strategy.valid_until.iso8601,
          created_at: strategy.created_at.iso8601,
          stale: strategy.stale?
        }
      end

      def recent_decisions
        TradingDecision.recent.limit(5).map do |d|
          {
            id: d.id,
            symbol: d.symbol,
            operation: d.operation,
            direction: d.direction,
            confidence: d.confidence&.to_f,
            status: d.status,
            reasoning: d.reasoning&.truncate(100),
            created_at: d.created_at.iso8601
          }
        end
      end

      def system_status
        # Check last market snapshot
        last_snapshot = MarketSnapshot.recent.first
        last_decision = TradingDecision.recent.first
        last_macro = MacroStrategy.recent.first

        {
          market_data: {
            healthy: last_snapshot && last_snapshot.captured_at > 5.minutes.ago,
            last_update: last_snapshot&.captured_at&.iso8601
          },
          trading_cycle: {
            healthy: last_decision && last_decision.created_at > 15.minutes.ago,
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
    end
  end
end
