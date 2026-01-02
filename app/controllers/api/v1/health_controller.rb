# frozen_string_literal: true

module Api
  module V1
    # Health endpoint providing application status and trading configuration.
    # Used by the frontend to display consistent status across all pages.
    class HealthController < ApplicationController
      def show
        render json: {
          status: "ok",
          version: Backend::VERSION,
          environment: Rails.env,
          paper_trading: Settings.trading.paper_trading,
          trading_allowed: trading_allowed?,
          timestamp: Time.current.iso8601
        }
      end

      private

      # @return [Boolean] whether trading is allowed (circuit breaker not triggered)
      def trading_allowed?
        return true unless defined?(Risk::CircuitBreaker)

        Risk::CircuitBreaker.new.trading_allowed?
      end
    end
  end
end
