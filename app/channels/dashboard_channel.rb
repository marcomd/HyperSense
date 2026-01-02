# frozen_string_literal: true

# WebSocket channel for real-time dashboard updates
#
# Broadcasts:
#   - market_update: New market data (prices, indicators)
#   - position_update: Position changes (opened, closed, PnL updates)
#   - decision_update: New trading decisions
#   - macro_strategy_update: New macro strategy
#   - system_status_update: System health changes
#
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard"
    logger.info "Client subscribed to dashboard channel"
  end

  def unsubscribed
    logger.info "Client unsubscribed from dashboard channel"
  end

  # Broadcast helpers (call from jobs/services)
  class << self
    def broadcast_market_update(data)
      ActionCable.server.broadcast("dashboard", {
        type: "market_update",
        data: data,
        timestamp: Time.current.iso8601
      })
    end

    def broadcast_position_update(position, action:)
      ActionCable.server.broadcast("dashboard", {
        type: "position_update",
        action: action, # opened, closed, updated
        data: serialize_position(position),
        timestamp: Time.current.iso8601
      })
    end

    def broadcast_decision(decision)
      ActionCable.server.broadcast("dashboard", {
        type: "decision_update",
        data: serialize_decision(decision),
        timestamp: Time.current.iso8601
      })
    end

    def broadcast_macro_strategy(strategy)
      ActionCable.server.broadcast("dashboard", {
        type: "macro_strategy_update",
        data: serialize_macro_strategy(strategy),
        timestamp: Time.current.iso8601
      })
    end

    def broadcast_system_status(status)
      ActionCable.server.broadcast("dashboard", {
        type: "system_status_update",
        data: status,
        timestamp: Time.current.iso8601
      })
    end

    private

    def serialize_position(position)
      {
        id: position.id,
        symbol: position.symbol,
        direction: position.direction,
        size: position.size.to_f,
        entry_price: position.entry_price.to_f,
        current_price: position.current_price&.to_f,
        unrealized_pnl: position.unrealized_pnl&.to_f,
        pnl_percent: position.pnl_percent,
        status: position.status,
        stop_loss_price: position.stop_loss_price&.to_f,
        take_profit_price: position.take_profit_price&.to_f,
        leverage: position.leverage,
        close_reason: position.close_reason,
        realized_pnl: position.realized_pnl&.to_f
      }
    end

    def serialize_decision(decision)
      {
        id: decision.id,
        symbol: decision.symbol,
        operation: decision.operation,
        direction: decision.direction,
        confidence: decision.confidence&.to_f,
        status: decision.status,
        reasoning: decision.reasoning&.truncate(150),
        created_at: decision.created_at.iso8601
      }
    end

    def serialize_macro_strategy(strategy)
      {
        id: strategy.id,
        bias: strategy.bias,
        risk_tolerance: strategy.risk_tolerance.to_f,
        market_narrative: strategy.market_narrative,
        valid_until: strategy.valid_until.iso8601,
        created_at: strategy.created_at.iso8601
      }
    end
  end
end
