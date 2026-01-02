# frozen_string_literal: true

module Api
  module V1
    # Exposes order history for the dashboard
    #
    # Orders track the lifecycle of trades submitted to Hyperliquid:
    # pending -> submitted -> filled/cancelled/failed
    class OrdersController < BaseController
      # GET /api/v1/orders
      # Returns orders with optional filters
      #
      # Query params:
      #   - status: pending, submitted, filled, partially_filled, cancelled, failed
      #   - symbol: filter by asset symbol
      #   - side: buy, sell
      #   - order_type: market, limit, stop_limit
      #   - from: start date (ISO8601)
      #   - to: end date (ISO8601)
      #   - page: pagination page number
      #   - per_page: items per page (max 100)
      def index
        orders = Order.recent.includes(:trading_decision, :position)
        orders = filter_orders(orders)

        result = paginate(orders)
        render json: {
          orders: result[:data].map { |o| serialize_order(o) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/orders/:id
      # Returns a single order with full details
      def show
        order = Order.find(params[:id])
        render json: { order: serialize_order(order, detailed: true) }
      end

      # GET /api/v1/orders/active
      # Returns pending and submitted orders (orders that are still "alive")
      def active
        orders = Order.active.recent.includes(:trading_decision, :position)

        render json: {
          orders: orders.map { |o| serialize_order(o) }
        }
      end

      # GET /api/v1/orders/stats
      # Returns order statistics for the specified period
      #
      # Query params:
      #   - hours: lookback period (default 24, max 168)
      def stats
        hours = (params[:hours] || 24).to_i.clamp(1, 168)
        since = hours.hours.ago

        orders = Order.where("created_at >= ?", since)

        by_status = orders.group(:status).count
        by_symbol = orders.group(:symbol).count
        by_side = orders.group(:side).count
        by_type = orders.group(:order_type).count

        # Fill rate calculation
        fillable = orders.where(status: %w[filled partially_filled cancelled])
        filled_count = orders.where(status: "filled").count
        total_fillable = fillable.count
        fill_rate = total_fillable.positive? ? (filled_count.to_f / total_fillable * 100).round(1) : 0

        # Average fill price deviation
        filled_orders = orders.filled.where.not(price: nil, average_fill_price: nil)
        avg_slippage = calculate_average_slippage(filled_orders)

        render json: {
          period_hours: hours,
          total_orders: orders.count,
          by_status: by_status,
          by_symbol: by_symbol,
          by_side: by_side,
          by_type: by_type,
          fill_rate: fill_rate,
          active_count: Order.active.count,
          average_slippage_percent: avg_slippage
        }
      end

      private

      # Applies query filters to the orders collection
      #
      # @param orders [ActiveRecord::Relation] The base orders query
      # @return [ActiveRecord::Relation] The filtered orders query
      def filter_orders(orders)
        orders = orders.where(status: params[:status]) if params[:status].present?
        orders = orders.for_symbol(params[:symbol].upcase) if params[:symbol].present?
        orders = orders.where(side: params[:side]) if params[:side].present?
        orders = orders.where(order_type: params[:order_type]) if params[:order_type].present?
        orders = orders.where("created_at >= ?", Time.zone.parse(params[:from])) if params[:from].present?
        orders = orders.where("created_at <= ?", Time.zone.parse(params[:to])) if params[:to].present?
        orders
      end

      # Serializes an order for API response
      #
      # @param order [Order] The order to serialize
      # @param detailed [Boolean] Whether to include full details
      # @return [Hash] The serialized order data
      def serialize_order(order, detailed: false)
        data = {
          id: order.id,
          symbol: order.symbol,
          side: order.side,
          order_type: order.order_type,
          size: order.size.to_f,
          price: order.price&.to_f,
          stop_price: order.stop_price&.to_f,
          status: order.status,
          filled_size: order.filled_size&.to_f,
          average_fill_price: order.average_fill_price&.to_f,
          fill_percent: order.fill_percent,
          hyperliquid_order_id: order.hyperliquid_order_id,
          submitted_at: order.submitted_at&.iso8601,
          filled_at: order.filled_at&.iso8601,
          created_at: order.created_at.iso8601
        }

        if detailed
          data[:hyperliquid_response] = order.hyperliquid_response
          data[:trading_decision_id] = order.trading_decision_id
          data[:position_id] = order.position_id
          data[:remaining_size] = order.remaining_size.to_f
          data[:updated_at] = order.updated_at.iso8601

          # Include linked decision summary if present
          if order.trading_decision
            data[:trading_decision] = {
              id: order.trading_decision.id,
              operation: order.trading_decision.operation,
              direction: order.trading_decision.direction,
              confidence: order.trading_decision.confidence&.to_f
            }
          end

          # Include linked position summary if present
          if order.position
            data[:position] = {
              id: order.position.id,
              symbol: order.position.symbol,
              direction: order.position.direction,
              status: order.position.status
            }
          end
        end

        data
      end

      # Calculates average slippage percentage for filled limit orders
      #
      # @param orders [ActiveRecord::Relation] Filled orders with price and fill price
      # @return [Float, nil] Average slippage percentage or nil if no data
      def calculate_average_slippage(orders)
        return nil if orders.empty?

        slippages = orders.map do |order|
          next nil if order.price.nil? || order.price.zero?
          ((order.average_fill_price - order.price) / order.price * 100).abs
        end.compact

        return nil if slippages.empty?
        (slippages.sum / slippages.size).round(3)
      end
    end
  end
end
