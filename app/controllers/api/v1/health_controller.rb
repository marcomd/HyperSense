# frozen_string_literal: true

module Api
  module V1
    # Health endpoint providing application status and trading configuration.
    # Used by the frontend to display consistent status across all pages.
    class HealthController < ApplicationController
      def show
        mode = TradingMode.current

        render json: {
          status: "ok",
          version: Backend::VERSION,
          environment: Rails.env,
          paper_trading: Settings.trading.paper_trading,
          trading_allowed: mode.can_open? || mode.can_close?,
          trading_mode: mode.mode,
          can_open_positions: mode.can_open?,
          can_close_positions: mode.can_close?,
          timestamp: Time.current.iso8601
        }
      end
    end
  end
end
