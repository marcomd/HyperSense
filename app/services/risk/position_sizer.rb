# frozen_string_literal: true

module Risk
  # Calculates optimal position size based on risk parameters
  #
  # Uses the "percent risk" position sizing method:
  # - Define maximum risk per trade (e.g., 1% of account)
  # - Calculate position size that risks exactly that amount
  #
  # Formula: size = (account_value * max_risk_pct) / abs(entry_price - stop_loss)
  #
  # @example
  #   sizer = Risk::PositionSizer.new
  #   result = sizer.calculate(
  #     entry_price: 100_000,
  #     stop_loss: 95_000,
  #     direction: "long"
  #   )
  #   result[:size]       # => 0.02 (BTC)
  #   result[:risk_amount] # => 100 (USD)
  #
  class PositionSizer
    # Decimal precision for different value types
    BTC_DECIMAL_PRECISION = 8
    USD_DECIMAL_PRECISION = 2

    def initialize(account_manager: nil)
      @account_manager = account_manager || Execution::AccountManager.new
      @logger = Rails.logger
    end

    # Calculate optimal position size based on risk
    # @param entry_price [Numeric] Expected entry price
    # @param stop_loss [Numeric, nil] Stop-loss price
    # @param direction [String] "long" or "short"
    # @param max_risk_pct [Numeric, nil] Override max risk percentage
    # @param account_value [Numeric, nil] Override account value
    # @return [Hash, nil] { size:, risk_amount:, capped: } or nil if cannot calculate
    def calculate(entry_price:, stop_loss:, direction:, max_risk_pct: nil, account_value: nil)
      return nil if stop_loss.nil?

      account_value ||= fetch_account_value
      return nil if account_value.nil? || account_value.zero?

      max_risk_pct ||= Settings.risk.max_risk_per_trade
      risk_per_unit = (entry_price - stop_loss).abs.to_d

      return nil if risk_per_unit.zero?

      max_risk_amount = (account_value * max_risk_pct).to_d
      calculated_size = (max_risk_amount / risk_per_unit).round(BTC_DECIMAL_PRECISION)

      # Cap at max position size
      max_size = Settings.risk.max_position_size.to_d
      capped = calculated_size > max_size
      final_size = [ calculated_size, max_size ].min

      # Recalculate actual risk if capped
      actual_risk = (final_size * risk_per_unit).round(USD_DECIMAL_PRECISION)

      @logger.info "[PositionSizer] #{direction} entry=#{entry_price} sl=#{stop_loss} " \
                   "size=#{final_size} risk=$#{actual_risk}#{capped ? ' (capped)' : ''}"

      {
        size: final_size.to_f.round(BTC_DECIMAL_PRECISION),
        risk_amount: actual_risk.to_f,
        risk_per_unit: risk_per_unit.to_f,
        capped: capped
      }
    end

    # Calculate optimal size for a trading decision
    # @param decision [TradingDecision] Trading decision with stop_loss
    # @param entry_price [Numeric] Expected entry price
    # @return [Hash, nil] Position size result or nil
    def optimal_size_for_decision(decision, entry_price:)
      calculate(
        entry_price: entry_price,
        stop_loss: decision.stop_loss,
        direction: decision.direction
      )
    end

    private

    def fetch_account_value
      state = @account_manager.fetch_account_state
      state[:account_value]
    rescue StandardError => e
      @logger.error "[PositionSizer] Failed to fetch account value: #{e.message}"
      nil
    end
  end
end
