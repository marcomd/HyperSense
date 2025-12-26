# frozen_string_literal: true

# WebSocket channel for real-time market data updates
#
# Supports subscribing to specific symbols or all symbols
#
# Usage from frontend:
#   subscription = cable.subscriptions.create({ channel: "MarketsChannel" })
#   subscription = cable.subscriptions.create({ channel: "MarketsChannel", symbol: "BTC" })
#
class MarketsChannel < ApplicationCable::Channel
  def subscribed
    if params[:symbol].present?
      symbol = params[:symbol].upcase
      stream_from "markets:#{symbol}"
      logger.info "Client subscribed to markets:#{symbol}"
    else
      stream_from "markets:all"
      logger.info "Client subscribed to markets:all"
    end
  end

  def unsubscribed
    logger.info "Client unsubscribed from markets channel"
  end

  # Broadcast helpers (call from MarketSnapshotJob)
  class << self
    # Broadcast to all market subscribers
    def broadcast_all(snapshots_data)
      ActionCable.server.broadcast("markets:all", {
        type: "market_data",
        assets: snapshots_data,
        timestamp: Time.current.iso8601
      })
    end

    # Broadcast to specific symbol subscribers
    def broadcast_symbol(symbol, data)
      ActionCable.server.broadcast("markets:#{symbol.upcase}", {
        type: "market_data",
        symbol: symbol.upcase,
        data: data,
        timestamp: Time.current.iso8601
      })
    end

    # Broadcast price update for all assets (from MarketSnapshotJob)
    def broadcast_snapshots(snapshots)
      all_data = snapshots.map { |s| serialize_snapshot(s) }

      # Broadcast to all subscribers
      broadcast_all(all_data)

      # Broadcast to individual symbol subscribers
      snapshots.each do |snapshot|
        broadcast_symbol(snapshot.symbol, serialize_snapshot(snapshot))
      end
    end

    private

    def serialize_snapshot(snapshot)
      indicators = snapshot.indicators || {}

      {
        symbol: snapshot.symbol,
        price: snapshot.price.to_f,
        rsi_14: indicators["rsi_14"]&.round(2),
        rsi_signal: snapshot.rsi_signal,
        macd_signal: snapshot.macd_signal,
        ema_20: indicators["ema_20"]&.round(2),
        ema_50: indicators["ema_50"]&.round(2),
        above_ema_50: snapshot.above_ema?(50),
        captured_at: snapshot.captured_at.iso8601
      }
    end
  end
end
