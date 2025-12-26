# frozen_string_literal: true

module Api
  module V1
    # Exposes macro strategy data for the dashboard
    class MacroStrategiesController < BaseController
      # GET /api/v1/macro_strategies
      # Returns recent macro strategies
      def index
        strategies = MacroStrategy.recent
        result = paginate(strategies)

        render json: {
          strategies: result[:data].map { |s| serialize_strategy(s) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/macro_strategies/current
      # Returns the active macro strategy
      def current
        strategy = MacroStrategy.active

        if strategy
          render json: { strategy: serialize_strategy(strategy, detailed: true) }
        else
          render json: {
            strategy: nil,
            needs_refresh: true,
            message: "No active macro strategy. Next refresh will generate one."
          }
        end
      end

      # GET /api/v1/macro_strategies/:id
      def show
        strategy = MacroStrategy.find(params[:id])
        render json: { strategy: serialize_strategy(strategy, detailed: true) }
      end

      private

      def serialize_strategy(strategy, detailed: false)
        data = {
          id: strategy.id,
          bias: strategy.bias,
          risk_tolerance: strategy.risk_tolerance.to_f,
          market_narrative: strategy.market_narrative,
          valid_until: strategy.valid_until.iso8601,
          stale: strategy.stale?,
          created_at: strategy.created_at.iso8601
        }

        if detailed
          data[:key_levels] = strategy.key_levels
          data[:context_used] = strategy.context_used
          data[:llm_response] = strategy.llm_response
        end

        data
      end
    end
  end
end
