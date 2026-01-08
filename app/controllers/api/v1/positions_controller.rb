# frozen_string_literal: true

module Api
  module V1
    # Exposes position data for the dashboard
    class PositionsController < BaseController
      # GET /api/v1/positions
      # Returns all positions with optional filters
      #
      # Query params:
      #   - status: open, closed, closing (default: all)
      #   - symbol: filter by asset symbol
      #   - page: pagination page number
      #   - per_page: items per page (max 100)
      def index
        positions = Position.recent.includes(orders: :trading_decision)
        positions = positions.where(status: params[:status]) if params[:status].present?
        positions = positions.for_symbol(params[:symbol].upcase) if params[:symbol].present?

        result = paginate(positions)
        render json: {
          positions: result[:data].map { |p| serialize_position(p) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/positions/open
      # Returns only open positions with fee information
      def open
        positions = Position.open.recent.includes(orders: :trading_decision)

        total_fees = positions.sum(&:total_fees).round(2)
        gross_pnl = positions.sum(&:unrealized_pnl).to_f.round(2)

        render json: {
          positions: positions.map { |p| serialize_position(p) },
          summary: {
            count: positions.count,
            total_pnl: gross_pnl, # Keep for backward compatibility
            gross_pnl: gross_pnl,
            total_fees: total_fees,
            net_pnl: (gross_pnl - total_fees).round(2),
            total_margin: positions.sum(&:margin_used).to_f.round(2)
          }
        }
      end

      # GET /api/v1/positions/:id
      def show
        position = Position.includes(orders: :trading_decision).find(params[:id])
        render json: { position: serialize_position(position, detailed: true) }
      end

      # GET /api/v1/positions/performance
      # Returns equity curve data for charting with fee-adjusted metrics
      def performance
        days = (params[:days] || 30).to_i.clamp(1, 365)
        since = days.days.ago.beginning_of_day

        # Group closed positions by day and calculate cumulative PnL
        daily_pnl = Position.closed
                            .where("closed_at >= ?", since)
                            .group("DATE(closed_at)")
                            .sum(:realized_pnl)

        # Calculate fees for positions closed each day
        fee_calculator = Costs::TradingFeeCalculator.new

        # Build equity curve with fee data
        equity_curve = []
        cumulative = 0
        cumulative_fees = 0

        (since.to_date..Date.current).each do |date|
          pnl = daily_pnl[date] || 0
          cumulative += pnl.to_f

          # Calculate fees for positions closed on this day
          day_positions = Position.closed.where(closed_at: date.all_day)
          day_fees = day_positions.sum { |p| fee_calculator.for_position(p)[:total_fee] }
          cumulative_fees += day_fees

          equity_curve << {
            date: date.to_s,
            daily_pnl: pnl.to_f.round(2),
            daily_fees: day_fees.round(4),
            cumulative_pnl: cumulative.round(2),
            cumulative_fees: cumulative_fees.round(4),
            cumulative_net_pnl: (cumulative - cumulative_fees).round(2)
          }
        end

        # Calculate statistics
        closed_positions = Position.closed.where("closed_at >= ?", since)
        wins = closed_positions.where("realized_pnl > 0").count
        losses = closed_positions.where("realized_pnl < 0").count
        total = wins + losses

        render json: {
          equity_curve: equity_curve,
          statistics: {
            total_trades: total,
            wins: wins,
            losses: losses,
            win_rate: total.positive? ? (wins.to_f / total * 100).round(1) : 0,
            total_pnl: cumulative.round(2),
            total_fees: cumulative_fees.round(4),
            net_pnl: (cumulative - cumulative_fees).round(2),
            avg_win: wins.positive? ? closed_positions.where("realized_pnl > 0").average(:realized_pnl).to_f.round(2) : 0,
            avg_loss: losses.positive? ? closed_positions.where("realized_pnl < 0").average(:realized_pnl).to_f.round(2) : 0
          }
        }
      end

      private

      def serialize_position(position, detailed: false)
        data = {
          id: position.id,
          symbol: position.symbol,
          direction: position.direction,
          size: position.size.to_f,
          entry_price: position.entry_price.to_f,
          current_price: position.current_price&.to_f,
          leverage: position.leverage,
          margin_used: position.margin_used&.to_f,
          unrealized_pnl: position.unrealized_pnl&.to_f,
          pnl_percent: position.pnl_percent,
          status: position.status,
          stop_loss_price: position.stop_loss_price&.to_f,
          take_profit_price: position.take_profit_price&.to_f,
          risk_reward_ratio: position.risk_reward_ratio,
          opened_at: position.opened_at&.iso8601,
          closed_at: position.closed_at&.iso8601,
          close_reason: position.close_reason,
          realized_pnl: position.realized_pnl&.to_f,
          # Fee information
          fees: {
            entry_fee: position.entry_fee,
            exit_fee: position.exit_fee,
            total_fees: position.total_fees,
            net_pnl: position.net_pnl
          },
          # Decision context
          opening_decision: serialize_decision_summary(position, "open"),
          closing_decision: serialize_decision_summary(position, "close")
        }

        if detailed
          data[:risk_amount] = position.risk_amount&.to_f
          data[:liquidation_price] = position.liquidation_price&.to_f
          data[:stop_loss_distance_pct] = position.stop_loss_distance_pct
          data[:take_profit_distance_pct] = position.take_profit_distance_pct
          data[:notional_value] = position.notional_value.to_f
          data[:orders] = position.orders.recent.limit(10).map do |order|
            {
              id: order.id,
              order_type: order.order_type,
              side: order.side,
              size: order.size.to_f,
              status: order.status,
              created_at: order.created_at.iso8601
            }
          end
        end

        data
      end

      # Serializes a decision summary for position response
      # @param position [Position] The position to get decision from
      # @param operation [String] "open" or "close"
      # @return [Hash, nil] Decision summary or nil
      def serialize_decision_summary(position, operation)
        order = position.orders.find do |o|
          o.trading_decision&.operation == operation
        end
        decision = order&.trading_decision
        return nil unless decision

        {
          id: decision.id,
          confidence: decision.confidence&.to_f,
          reasoning: decision.reasoning&.truncate(200),
          risk_profile_name: decision.risk_profile_name,
          created_at: decision.created_at.iso8601
        }
      end
    end
  end
end
