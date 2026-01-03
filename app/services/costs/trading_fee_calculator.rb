# frozen_string_literal: true

module Costs
  # Calculates trading fees for positions and orders
  #
  # Hyperliquid fee structure:
  # - Taker: 0.0450% (market orders)
  # - Maker: 0.0150% (limit orders)
  #
  # Fees are applied on both entry and exit (round-trip).
  # Formula: fee = notional_value * fee_rate
  #
  # @example Calculate fees for a position
  #   calculator = Costs::TradingFeeCalculator.new
  #   result = calculator.for_position(position)
  #   result[:total_fee] # => 9.0 (USD)
  #
  # @example Estimate fees for a potential trade
  #   result = calculator.estimate(notional_value: 10_000, round_trip: true)
  #   result[:total_fee] # => 9.0 (USD)
  #
  class TradingFeeCalculator
    # Decimal precision for fee calculations
    FEE_PRECISION = 4

    # Calculate total fees across positions for a time period
    # @param since [Time, nil] Start of period (nil = all time)
    # @return [Hash] Fee breakdown with totals
    def total_fees(since: nil)
      positions = fetch_closed_positions(since: since)

      entry_fees = 0.0
      exit_fees = 0.0

      positions.each do |position|
        entry_fees += calculate_entry_fee(position)
        exit_fees += calculate_exit_fee(position)
      end

      # Include fees for currently open positions (entry only)
      open_entry = Position.open.sum { |p| calculate_entry_fee(p) }

      {
        entry_fees: entry_fees.round(FEE_PRECISION),
        exit_fees: exit_fees.round(FEE_PRECISION),
        open_position_entry_fees: open_entry.round(FEE_PRECISION),
        total: (entry_fees + exit_fees + open_entry).round(FEE_PRECISION),
        fee_rate: current_fee_rate,
        positions_counted: positions.size + Position.open.count
      }
    end

    # Calculate fees for a single position
    # @param position [Position] The position to calculate fees for
    # @return [Hash] Entry and exit fees with metadata
    def for_position(position)
      entry = calculate_entry_fee(position)
      exit_fee = position.closed? ? calculate_exit_fee(position) : estimate_exit_fee(position)

      {
        entry_fee: entry.round(FEE_PRECISION),
        exit_fee: exit_fee.round(FEE_PRECISION),
        total_fee: (entry + exit_fee).round(FEE_PRECISION),
        fee_rate: current_fee_rate,
        estimated: !position.closed?
      }
    end

    # Estimate fees for a potential trade
    # @param notional_value [Numeric] Trade size in USD
    # @param round_trip [Boolean] Include exit fee estimate (default: true)
    # @return [Hash] Estimated fees
    def estimate(notional_value:, round_trip: true)
      fee_rate = current_fee_rate
      entry = notional_value * fee_rate
      exit_fee = round_trip ? entry : 0.0

      {
        entry_fee: entry.round(FEE_PRECISION),
        exit_fee: exit_fee.round(FEE_PRECISION),
        total_fee: (entry + exit_fee).round(FEE_PRECISION),
        fee_rate: fee_rate
      }
    end

    private

    # Fetch closed positions for a time period
    # @param since [Time, nil] Start of period
    # @return [Array<Position>] Closed positions
    def fetch_closed_positions(since:)
      scope = Position.closed
      scope = scope.where("closed_at >= ?", since) if since
      scope.to_a
    end

    # Calculate entry fee based on entry notional value
    # @param position [Position] The position
    # @return [Float] Entry fee in USD
    def calculate_entry_fee(position)
      notional = position.entry_price.to_f * position.size.to_f
      notional * current_fee_rate
    end

    # Calculate exit fee for closed position
    # @param position [Position] The closed position
    # @return [Float] Exit fee in USD
    def calculate_exit_fee(position)
      return 0.0 unless position.closed?

      exit_price = position.current_price || position.entry_price
      notional = exit_price.to_f * position.size.to_f
      notional * current_fee_rate
    end

    # Estimate exit fee for open position using current price
    # @param position [Position] The open position
    # @return [Float] Estimated exit fee in USD
    def estimate_exit_fee(position)
      exit_price = position.current_price || position.entry_price
      notional = exit_price.to_f * position.size.to_f
      notional * current_fee_rate
    end

    # Get current fee rate based on settings
    # @return [Float] Fee rate (e.g., 0.00045 for 0.045%)
    def current_fee_rate
      order_type = Settings.costs.trading.default_order_type.to_s

      if order_type == "maker"
        Settings.costs.trading.maker_fee_pct.to_f
      else
        Settings.costs.trading.taker_fee_pct.to_f
      end
    end
  end
end
