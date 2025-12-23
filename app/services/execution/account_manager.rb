# frozen_string_literal: true

module Execution
  # Manages account state and portfolio information from Hyperliquid
  #
  # Responsibilities:
  # - Fetch and format account state (balance, margin, positions)
  # - Check trading eligibility (margin, position limits)
  # - Calculate margin requirements
  # - Provide portfolio summary
  #
  class AccountManager
    def initialize(client: nil)
      @client = client || HyperliquidClient.new
      @logger = Rails.logger
    end

    # Fetch current account state from Hyperliquid
    # @return [Hash] Formatted account state
    def fetch_account_state
      @logger.info "[AccountManager] Fetching account state..."

      response = @client.user_state(@client.address)
      summary = response["crossMarginSummary"] || {}

      account_state = {
        account_value: summary["accountValue"]&.to_f || 0,
        margin_used: summary["totalMarginUsed"]&.to_f || 0,
        available_margin: summary["totalRawUsd"]&.to_f || 0,
        notional_position: summary["totalNtlPos"]&.to_f || 0,
        positions_count: (response["assetPositions"] || []).count,
        raw_response: response
      }

      log_success("sync_account", { address: @client.address }, account_state.except(:raw_response))

      @logger.info "[AccountManager] Account value: #{account_state[:account_value]}, " \
                   "Available: #{account_state[:available_margin]}"

      account_state
    rescue HyperliquidClient::HyperliquidApiError => e
      log_failure("sync_account", { address: @client.address }, e.message)
      raise
    end

    # Get full portfolio summary including local position data
    # @return [Hash] Portfolio summary
    def get_portfolio_summary
      account_state = fetch_account_state
      local_positions = Position.open

      {
        account_value: account_state[:account_value],
        margin_used: account_state[:margin_used],
        available_margin: account_state[:available_margin],
        open_positions: local_positions.count,
        total_unrealized_pnl: local_positions.sum(:unrealized_pnl).to_f,
        positions: local_positions.map do |pos|
          {
            symbol: pos.symbol,
            direction: pos.direction,
            size: pos.size.to_f,
            entry_price: pos.entry_price.to_f,
            unrealized_pnl: pos.unrealized_pnl.to_f,
            pnl_percent: pos.pnl_percent
          }
        end
      }
    end

    # Check if a new trade can be executed
    # @param margin_required [Numeric] Required margin for the trade
    # @return [Boolean] Whether trade is allowed
    def can_trade?(margin_required:)
      account_state = fetch_account_state

      # Check margin availability
      return false if account_state[:available_margin] < margin_required

      # Check position limit
      open_positions = Position.open.count
      return false if open_positions >= Settings.risk.max_open_positions

      true
    end

    # Calculate required margin for a position
    # @param size [Numeric] Position size
    # @param price [Numeric] Entry price
    # @param leverage [Integer, nil] Leverage (uses default if nil)
    # @return [Numeric] Required margin
    def margin_for_position(size:, price:, leverage: nil)
      leverage ||= Settings.risk.default_leverage
      (size * price) / leverage
    end

    # Get exposure summary by asset
    # @return [Hash] Symbol => exposure hash
    def exposure_by_asset
      Position.open.group_by(&:symbol).transform_values do |positions|
        {
          total_size: positions.sum(&:size).to_f,
          total_margin: positions.sum(&:margin_used).to_f,
          unrealized_pnl: positions.sum(&:unrealized_pnl).to_f,
          position_count: positions.count
        }
      end
    end

    private

    def log_success(action, request, response)
      ExecutionLog.log_success!(
        loggable: nil,
        action: action,
        request_payload: request,
        response_payload: response
      )
    end

    def log_failure(action, request, error)
      ExecutionLog.log_failure!(
        loggable: nil,
        action: action,
        request_payload: request,
        error_message: error
      )
    end
  end
end
