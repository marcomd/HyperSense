# frozen_string_literal: true

module Api
  module V1
    # Manages user-controlled trading modes.
    #
    # Allows users to switch between three modes:
    # - enabled: Normal operation (can open and close positions)
    # - exit_only: Only close positions (set automatically by circuit breaker)
    # - blocked: Complete halt (no opens or closes)
    #
    class TradingModesController < BaseController
      # GET /api/v1/trading_mode/current
      #
      # Returns the current trading mode and permissions.
      #
      # @return [JSON] { mode: { mode, reason, changed_by, updated_at }, can_open, can_close }
      def current
        mode = TradingMode.current

        render json: {
          mode: serialize_mode(mode),
          can_open: mode.can_open?,
          can_close: mode.can_close?
        }
      end

      # PUT /api/v1/trading_mode/switch
      #
      # Switches to a different trading mode.
      # Broadcasts the change via WebSocket for real-time dashboard updates.
      #
      # @param mode [String] Mode name (enabled, exit_only, or blocked)
      # @param reason [String, optional] Reason for the change
      # @return [JSON] { mode: {...}, can_open, can_close, message: "..." }
      def switch
        mode_name = params.require(:mode)
        reason = params[:reason]

        unless TradingMode::MODES.include?(mode_name)
          return render json: {
            error: "Invalid mode: #{mode_name}. Valid modes: #{TradingMode::MODES.join(', ')}"
          }, status: :unprocessable_entity
        end

        TradingMode.switch_to!(mode_name, changed_by: "dashboard", reason: reason)
        mode = TradingMode.current

        # Broadcast change via WebSocket
        DashboardChannel.broadcast_trading_mode_update(mode)

        render json: {
          mode: serialize_mode(mode),
          can_open: mode.can_open?,
          can_close: mode.can_close?,
          message: "Switched to #{mode_name} mode. Takes effect immediately."
        }
      end

      private

      # Serialize a TradingMode record for JSON response.
      #
      # @param mode [TradingMode] The mode to serialize
      # @return [Hash] Serialized mode data
      def serialize_mode(mode)
        {
          mode: mode.mode,
          reason: mode.reason,
          changed_by: mode.changed_by,
          updated_at: mode.updated_at.iso8601
        }
      end
    end
  end
end
