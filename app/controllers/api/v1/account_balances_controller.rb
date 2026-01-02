# frozen_string_literal: true

module Api
  module V1
    # Exposes account balance history for tracking deposits, withdrawals, and PnL
    #
    # AccountBalance records enable accurate PnL calculation by distinguishing
    # trading gains/losses from external fund movements.
    class AccountBalancesController < BaseController
      # GET /api/v1/account_balances
      # Returns balance history with optional filters
      #
      # Query params:
      #   - event_type: initial, sync, deposit, withdrawal, adjustment
      #   - from: start date (ISO8601)
      #   - to: end date (ISO8601)
      #   - page: pagination page number
      #   - per_page: items per page (max 100)
      def index
        balances = AccountBalance.recent
        balances = filter_balances(balances)

        result = paginate(balances)
        render json: {
          account_balances: result[:data].map { |b| serialize_balance(b) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/account_balances/:id
      # Returns a single balance record with full details
      def show
        balance = AccountBalance.find(params[:id])
        render json: { account_balance: serialize_balance(balance, detailed: true) }
      end

      # GET /api/v1/account_balances/summary
      # Returns current balance summary for dashboard
      def summary
        balance_service = Execution::BalanceSyncService.new
        balance_history = balance_service.balance_history

        render json: {
          initial_balance: balance_history[:initial_balance]&.round(2),
          current_balance: balance_history[:current_balance]&.round(2),
          total_deposits: balance_history[:total_deposits]&.round(2),
          total_withdrawals: balance_history[:total_withdrawals]&.round(2),
          calculated_pnl: balance_history[:calculated_pnl]&.round(2),
          last_sync: balance_history[:last_sync]&.iso8601,
          record_count: AccountBalance.count,
          deposits_count: AccountBalance.deposits.count,
          withdrawals_count: AccountBalance.withdrawals.count
        }
      end

      private

      # Applies query filters to the balances collection
      #
      # @param balances [ActiveRecord::Relation] The base balances query
      # @return [ActiveRecord::Relation] The filtered balances query
      def filter_balances(balances)
        balances = balances.by_event_type(params[:event_type]) if params[:event_type].present?
        balances = balances.where("recorded_at >= ?", Time.zone.parse(params[:from])) if params[:from].present?
        balances = balances.where("recorded_at <= ?", Time.zone.parse(params[:to])) if params[:to].present?
        balances
      end

      # Serializes an account balance for API response
      #
      # @param balance [AccountBalance] The balance to serialize
      # @param detailed [Boolean] Whether to include full details
      # @return [Hash] The serialized balance data
      def serialize_balance(balance, detailed: false)
        data = {
          id: balance.id,
          balance: balance.balance.to_f,
          previous_balance: balance.previous_balance&.to_f,
          delta: balance.delta&.to_f,
          event_type: balance.event_type,
          source: balance.source,
          notes: balance.notes,
          recorded_at: balance.recorded_at.iso8601,
          created_at: balance.created_at.iso8601
        }

        if detailed
          data[:hyperliquid_data] = balance.hyperliquid_data
          data[:updated_at] = balance.updated_at.iso8601
        end

        data
      end
    end
  end
end
