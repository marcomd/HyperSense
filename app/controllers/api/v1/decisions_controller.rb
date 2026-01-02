# frozen_string_literal: true

module Api
  module V1
    # Exposes trading decision logs for the dashboard
    class DecisionsController < BaseController
      # GET /api/v1/decisions
      # Returns trading decisions with optional filters
      #
      # Query params:
      #   - status: pending, approved, rejected, executed, failed
      #   - symbol: filter by asset symbol
      #   - operation: open, close, hold
      #   - page: pagination page number
      #   - per_page: items per page (max 100)
      def index
        decisions = TradingDecision.recent.includes(:macro_strategy)
        decisions = filter_decisions(decisions)

        result = paginate(decisions)
        render json: {
          decisions: result[:data].map { |d| serialize_decision(d) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/decisions/:id
      def show
        decision = TradingDecision.find(params[:id])
        render json: { decision: serialize_decision(decision, detailed: true) }
      end

      # GET /api/v1/decisions/recent
      # Returns last N decisions for quick dashboard view
      def recent
        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        decisions = TradingDecision.recent.limit(limit)

        render json: {
          decisions: decisions.map { |d| serialize_decision(d) }
        }
      end

      # GET /api/v1/decisions/stats
      # Returns decision statistics
      def stats
        hours = (params[:hours] || 24).to_i.clamp(1, 168)
        since = hours.hours.ago

        decisions = TradingDecision.where("created_at >= ?", since)

        by_status = decisions.group(:status).count
        by_symbol = decisions.group(:symbol).count
        by_operation = decisions.group(:operation).count

        avg_confidence = decisions.where.not(confidence: nil).average(:confidence)&.to_f&.round(3)

        # Execution success rate
        actionable = decisions.where(operation: %w[open close])
        executed = actionable.where(status: "executed").count
        total_actionable = actionable.count

        render json: {
          period_hours: hours,
          total_decisions: decisions.count,
          by_status: by_status,
          by_symbol: by_symbol,
          by_operation: by_operation,
          average_confidence: avg_confidence,
          execution_rate: total_actionable.positive? ? (executed.to_f / total_actionable * 100).round(1) : 0,
          rejection_reasons: decisions.rejected.group(:rejection_reason).count
        }
      end

      private

      # Applies query filters to the decisions collection
      #
      # Supports filtering by status, symbol, operation, and volatility_level.
      #
      # @param decisions [ActiveRecord::Relation] The base decisions query
      # @return [ActiveRecord::Relation] The filtered decisions query
      def filter_decisions(decisions)
        decisions = decisions.where(status: params[:status]) if params[:status].present?
        decisions = decisions.for_symbol(params[:symbol].upcase) if params[:symbol].present?
        decisions = decisions.where(operation: params[:operation]) if params[:operation].present?
        decisions = decisions.where(volatility_level: params[:volatility_level]) if params[:volatility_level].present?
        decisions
      end

      # Serializes a trading decision for API response
      #
      # Includes core decision data plus volatility fields. The llm_model field
      # is only included in detailed responses to keep list views compact.
      #
      # @param decision [TradingDecision] The decision to serialize
      # @param detailed [Boolean] Whether to include full context details
      # @return [Hash] The serialized decision data
      def serialize_decision(decision, detailed: false)
        data = {
          id: decision.id,
          symbol: decision.symbol,
          operation: decision.operation,
          direction: decision.direction,
          confidence: decision.confidence&.to_f,
          status: decision.status,
          executed: decision.executed,
          rejection_reason: decision.rejection_reason,
          leverage: decision.leverage,
          stop_loss: decision.stop_loss,
          take_profit: decision.take_profit,
          reasoning: decision.reasoning,
          volatility_level: decision.volatility_level,
          atr_value: decision.atr_value&.to_f,
          next_cycle_interval: decision.next_cycle_interval,
          created_at: decision.created_at.iso8601
        }

        if detailed
          data[:llm_model] = decision.llm_model
          data[:target_position] = decision.target_position
          data[:context_sent] = decision.context_sent
          data[:llm_response] = decision.llm_response
          data[:parsed_decision] = decision.parsed_decision
          data[:macro_strategy] = decision.macro_strategy ? {
            id: decision.macro_strategy.id,
            bias: decision.macro_strategy.bias,
            risk_tolerance: decision.macro_strategy.risk_tolerance.to_f
          } : nil
        end

        data
      end
    end
  end
end
