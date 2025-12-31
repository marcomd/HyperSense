# frozen_string_literal: true

module Api
  module V1
    # Cost management and tracking endpoints
    #
    # Provides detailed cost breakdown for trading fees, LLM usage, and server costs.
    # All calculations are done on-the-fly without database storage.
    #
    class CostsController < BaseController
      # GET /api/v1/costs/summary
      # Returns detailed cost breakdown for a period
      #
      # Query params:
      #   - period: today, week, month, all (default: today)
      def summary
        period = params[:period]&.to_sym || :today

        calculator = Costs::Calculator.new
        costs_summary = calculator.summary(period: period)
        net_pnl = calculator.net_pnl(period: period)

        render json: {
          costs: costs_summary,
          pnl: net_pnl
        }
      rescue ArgumentError => e
        render json: { error: e.message }, status: :bad_request
      end

      # GET /api/v1/costs/llm
      # Returns LLM cost details and current pricing
      def llm
        calculator = Costs::LLMCostCalculator.new

        render json: {
          today: calculator.estimated_costs(since: Time.current.beginning_of_day),
          week: calculator.estimated_costs(since: 7.days.ago.beginning_of_day),
          month: calculator.estimated_costs(since: 30.days.ago.beginning_of_day),
          pricing: calculator.current_pricing
        }
      end

      # GET /api/v1/costs/trading
      # Returns trading fee details
      def trading
        calculator = Costs::TradingFeeCalculator.new

        render json: {
          today: calculator.total_fees(since: Time.current.beginning_of_day),
          week: calculator.total_fees(since: 7.days.ago.beginning_of_day),
          month: calculator.total_fees(since: 30.days.ago.beginning_of_day),
          fee_rates: {
            taker: Settings.costs.trading.taker_fee_pct.to_f,
            maker: Settings.costs.trading.maker_fee_pct.to_f,
            current: Settings.costs.trading.default_order_type
          }
        }
      end
    end
  end
end
