# frozen_string_literal: true

module Api
  module V1
    # Exposes execution logs for the dashboard
    # Provides audit trail for all execution operations (orders, syncs, risk triggers)
    class ExecutionLogsController < BaseController
      # GET /api/v1/execution_logs
      # Returns execution logs with optional filters (includes payload details for expandable rows)
      #
      # Query params:
      #   - status: success, failure
      #   - log_action: place_order, cancel_order, modify_order, sync_position, sync_account, risk_trigger
      #   - start_date: filter logs from this date (ISO 8601)
      #   - end_date: filter logs until this date (ISO 8601)
      #   - page: pagination page number
      #   - per_page: items per page (max 100)
      def index
        logs = ExecutionLog.recent
        logs = filter_execution_logs(logs)

        result = paginate(logs)
        render json: {
          execution_logs: result[:data].map { |log| serialize_execution_log(log, detailed: true) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/execution_logs/:id
      # Returns detailed execution log with payloads
      def show
        log = ExecutionLog.find(params[:id])
        render json: { execution_log: serialize_execution_log(log, detailed: true) }
      end

      # GET /api/v1/execution_logs/stats
      # Returns execution statistics for a given time period
      #
      # Query params:
      #   - hours: time period in hours (default 24, max 168)
      def stats
        hours = (params[:hours] || 24).to_i.clamp(1, 168)
        since = hours.hours.ago

        logs = ExecutionLog.where("executed_at >= ?", since)

        render json: {
          period_hours: hours,
          total_logs: logs.count,
          by_status: logs.group(:status).count,
          by_action: logs.group(:action).count,
          success_rate: calculate_success_rate(logs)
        }
      end

      private

      # Applies filters to the execution logs query
      #
      # @param logs [ActiveRecord::Relation] base query
      # @return [ActiveRecord::Relation] filtered query
      def filter_execution_logs(logs)
        logs = logs.where(status: params[:status]) if params[:status].present?
        logs = logs.for_action(params[:log_action]) if params[:log_action].present?
        logs = logs.where("executed_at >= ?", Time.zone.parse(params[:start_date])) if params[:start_date].present?
        logs = logs.where("executed_at <= ?", Time.zone.parse(params[:end_date])) if params[:end_date].present?
        logs
      end

      # Serializes an execution log for JSON response
      #
      # @param log [ExecutionLog] the log to serialize
      # @param detailed [Boolean] whether to include payload details
      # @return [Hash] serialized log data
      def serialize_execution_log(log, detailed: false)
        data = {
          id: log.id,
          action: log.action,
          status: log.status,
          executed_at: log.executed_at&.iso8601,
          created_at: log.created_at&.iso8601,
          loggable_type: log.loggable_type,
          loggable_id: log.loggable_id
        }

        if detailed
          data[:request_payload] = log.request_payload
          data[:response_payload] = log.response_payload
          data[:error_message] = log.error_message
          data[:duration_ms] = log.duration_ms
        end

        data
      end

      # Calculates the success rate for a collection of logs
      #
      # @param logs [ActiveRecord::Relation] logs to calculate rate for
      # @return [Float] success rate as percentage (0.0-100.0)
      def calculate_success_rate(logs)
        total = logs.count
        return 0.0 if total.zero?

        (logs.successful.count.to_f / total * 100).round(2)
      end
    end
  end
end
