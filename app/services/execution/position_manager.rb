# frozen_string_literal: true

module Execution
  # Manages trading positions and synchronization with Hyperliquid
  #
  # Responsibilities:
  # - Sync local positions with Hyperliquid state
  # - Create, update, and close positions
  # - Update prices and unrealized PnL
  # - Query position state
  #
  class PositionManager
    def initialize(client: nil)
      @client = client || HyperliquidClient.new
      @logger = Rails.logger
    end

    # Sync local positions with Hyperliquid state
    # Creates new positions, updates existing, closes orphaned
    # @return [Hash] Sync results
    def sync_from_hyperliquid
      @logger.info "[PositionManager] Syncing positions from Hyperliquid..."

      response = @client.user_state(@client.address)
      hl_positions = response["assetPositions"] || []

      synced_symbols = []
      results = { created: 0, updated: 0, closed: 0 }

      hl_positions.each do |asset_position|
        pos_data = asset_position["position"]
        next unless pos_data

        symbol = pos_data["coin"]
        next unless symbol # Skip if no symbol

        # Validate entry price is present (required field)
        entry_px = pos_data["entryPx"]
        if entry_px.nil?
          @logger.warn "[PositionManager] Skipping position - missing entryPx for #{symbol}"
          next
        end

        size = pos_data["szi"]&.to_d || 0
        if size.zero?
          @logger.warn "[PositionManager] Skipping position - zero size for #{symbol}"
          next
        end

        synced_symbols << symbol

        direction = size.positive? ? "long" : "short"
        size = size.abs

        position = Position.find_or_initialize_by(symbol: symbol, status: "open")

        if position.new_record?
          results[:created] += 1
        else
          results[:updated] += 1
        end

        position.assign_attributes(
          direction: direction,
          size: size,
          entry_price: entry_px.to_d,
          current_price: pos_data["markPx"]&.to_d,
          unrealized_pnl: pos_data["unrealizedPnl"]&.to_d || 0,
          liquidation_price: pos_data["liquidationPx"]&.to_d,
          margin_used: pos_data["marginUsed"]&.to_d,
          leverage: pos_data.dig("leverage", "value")&.to_i || Settings.risk.default_leverage,
          hyperliquid_data: pos_data,
          opened_at: position.opened_at || Time.current
        )
        position.save!
      end

      # Close positions that no longer exist in Hyperliquid
      orphaned = Position.open.where.not(symbol: synced_symbols)
      orphaned.find_each do |position|
        position.close!
        results[:closed] += 1
      end

      log_success("sync_position", { address: @client.address }, results)

      @logger.info "[PositionManager] Sync complete: #{results}"
      results
    end

    # Find existing position or create new one
    # @param symbol [String] Asset symbol
    # @param direction [String] long/short
    # @param attrs [Hash] Additional attributes for new position
    # @return [Position]
    def find_or_create_position(symbol, direction, **attrs)
      position = Position.find_by(symbol: symbol, direction: direction, status: "open")
      return position if position

      open_position(symbol: symbol, direction: direction, **attrs)
    end

    # Create a new open position
    # @param symbol [String] Asset symbol
    # @param direction [String] long/short
    # @param size [Numeric] Position size
    # @param entry_price [Numeric] Entry price
    # @param leverage [Integer] Leverage
    # @param stop_loss_price [Numeric, nil] Stop-loss price
    # @param take_profit_price [Numeric, nil] Take-profit price
    # @param risk_amount [Numeric, nil] Dollar amount at risk
    # @return [Position]
    def open_position(symbol:, direction:, size:, entry_price:, leverage: nil,
                      stop_loss_price: nil, take_profit_price: nil, risk_amount: nil)
      leverage ||= Settings.risk.default_leverage
      margin_used = (size * entry_price) / leverage

      Position.create!(
        symbol: symbol,
        direction: direction,
        size: size,
        entry_price: entry_price,
        current_price: entry_price,
        leverage: leverage,
        margin_used: margin_used,
        unrealized_pnl: 0,
        status: "open",
        opened_at: Time.current,
        stop_loss_price: stop_loss_price,
        take_profit_price: take_profit_price,
        risk_amount: risk_amount
      )
    end

    # Close a position
    # @param position [Position] Position to close
    def close_position(position)
      position.close!
      @logger.info "[PositionManager] Closed position #{position.id} (#{position.symbol})"
    end

    # Update current prices for all open positions
    def update_prices
      mids = @client.all_mids

      Position.open.find_each do |position|
        price_str = mids[position.symbol]
        next unless price_str

        new_price = price_str.to_d
        position.update_current_price!(new_price)
      end

      @logger.info "[PositionManager] Updated prices for #{Position.open.count} positions"
    end

    # Check if there's an open position for a symbol
    # @param symbol [String] Asset symbol
    # @param direction [String, nil] Optional direction filter
    # @return [Boolean]
    def has_open_position?(symbol, direction: nil)
      scope = Position.open.for_symbol(symbol)
      scope = scope.where(direction: direction) if direction
      scope.exists?
    end

    # Get open position for symbol
    # @param symbol [String] Asset symbol
    # @return [Position, nil]
    def get_open_position(symbol)
      Position.open.for_symbol(symbol).first
    end

    # Get all open positions
    # @return [ActiveRecord::Relation<Position>]
    def open_positions
      Position.open.recent
    end

    # Count of open positions
    # @return [Integer]
    def open_positions_count
      Position.open.count
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
  end
end
