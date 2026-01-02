# frozen_string_literal: true

module Risk
  # Centralized risk management validation service
  #
  # Consolidates all risk checks into a single service:
  # - Confidence threshold validation
  # - Position limits
  # - Leverage limits
  # - Margin requirements
  # - Risk/reward ratio validation
  #
  # @example
  #   manager = Risk::RiskManager.new
  #   result = manager.validate(decision, entry_price: 100_000)
  #   if result.approved?
  #     # Execute trade
  #   else
  #     decision.reject!(result.rejection_reason)
  #   end
  #
  class RiskManager
    # Default fallback for minimum risk/reward ratio (lowered from 2.0 to allow more trades)
    DEFAULT_MIN_RISK_REWARD_RATIO = 1.5

    # Result object for validation checks
    ValidationResult = Struct.new(:valid, :reason, keyword_init: true) do
      def approved?
        valid
      end

      def rejection_reason
        reason
      end
    end

    def initialize(account_manager: nil, position_manager: nil)
      @account_manager = account_manager || Execution::AccountManager.new
      @position_manager = position_manager || Execution::PositionManager.new
      @logger = Rails.logger
    end

    # Validate a trading decision against all risk rules
    # @param decision [TradingDecision] The decision to validate
    # @param entry_price [Numeric] Expected entry price
    # @return [ValidationResult]
    def validate(decision, entry_price:)
      # Check operation type
      if decision.operation == "hold"
        return ValidationResult.new(valid: false, reason: "Cannot execute hold operations")
      end

      # Check confidence threshold
      result = validate_confidence(decision)
      return result unless result.approved?

      # Check leverage limits
      result = validate_leverage(decision)
      return result unless result.approved?

      # Check max open positions
      result = validate_position_limit
      return result unless result.approved?

      # Operation-specific checks
      if decision.operation == "open"
        result = validate_open_operation(decision, entry_price)
        return result unless result.approved?

        # Check risk/reward ratio if SL/TP provided
        if decision.stop_loss && decision.take_profit
          result = validate_risk_reward(
            entry_price: entry_price,
            stop_loss: decision.stop_loss,
            take_profit: decision.take_profit,
            direction: decision.direction
          )
          return result unless result.approved?
        end
      elsif decision.operation == "close"
        result = validate_close_operation(decision)
        return result unless result.approved?
      end

      ValidationResult.new(valid: true)
    end

    # Validate risk/reward ratio for a trade
    # @param entry_price [Numeric] Expected entry price
    # @param stop_loss [Numeric, nil] Stop-loss price
    # @param take_profit [Numeric, nil] Take-profit price
    # @param direction [String] "long" or "short"
    # @return [ValidationResult]
    def validate_risk_reward(entry_price:, stop_loss:, take_profit:, direction:)
      return ValidationResult.new(valid: true) if stop_loss.nil? || take_profit.nil?

      risk = (entry_price - stop_loss).abs
      reward = (take_profit - entry_price).abs

      return ValidationResult.new(valid: true) if risk.zero?

      ratio = reward / risk
      min_ratio = min_risk_reward_ratio

      if ratio < min_ratio
        if enforce_risk_reward_ratio?
          return ValidationResult.new(
            valid: false,
            reason: "Poor risk/reward ratio: #{ratio.round(2)} (minimum: #{min_ratio})"
          )
        else
          @logger.warn "[RiskManager] Poor risk/reward ratio: #{ratio.round(2)} for #{direction} trade (warning only)"
        end
      end

      ValidationResult.new(valid: true)
    end

    # Calculate dollar amount at risk for a trade
    # @param size [Numeric] Position size
    # @param entry_price [Numeric] Entry price
    # @param stop_loss [Numeric, nil] Stop-loss price
    # @param direction [String] "long" or "short"
    # @return [Numeric, nil] Dollar risk amount
    def calculate_risk_amount(size:, entry_price:, stop_loss:, direction:)
      return nil if stop_loss.nil?

      price_risk = (entry_price - stop_loss).abs
      (size * price_risk).to_d
    end

    private

    def validate_confidence(decision)
      min_confidence = Settings.risk.min_confidence
      confidence = decision.confidence || 0

      if confidence < min_confidence
        ValidationResult.new(
          valid: false,
          reason: "Confidence #{confidence} below minimum #{min_confidence}"
        )
      else
        ValidationResult.new(valid: true)
      end
    end

    def validate_leverage(decision)
      max_leverage = Settings.risk.max_leverage
      leverage = decision.leverage || Settings.risk.default_leverage

      if leverage > max_leverage
        ValidationResult.new(
          valid: false,
          reason: "Leverage #{leverage} exceeds maximum #{max_leverage}"
        )
      else
        ValidationResult.new(valid: true)
      end
    end

    def validate_position_limit
      max_positions = Settings.risk.max_open_positions
      current_count = @position_manager.open_positions_count

      if current_count >= max_positions
        ValidationResult.new(
          valid: false,
          reason: "At max open positions (#{current_count}/#{max_positions})"
        )
      else
        ValidationResult.new(valid: true)
      end
    end

    def validate_open_operation(decision, entry_price)
      # Check for existing position
      if @position_manager.has_open_position?(decision.symbol)
        return ValidationResult.new(
          valid: false,
          reason: "Already have existing position for #{decision.symbol}"
        )
      end

      # Check margin availability
      size = decision.target_position || Settings.risk.max_position_size
      leverage = decision.leverage || Settings.risk.default_leverage
      margin_required = @account_manager.margin_for_position(
        size: size, price: entry_price, leverage: leverage
      )

      unless @account_manager.can_trade?(margin_required: margin_required)
        return ValidationResult.new(
          valid: false,
          reason: "Insufficient margin or position limit reached"
        )
      end

      ValidationResult.new(valid: true)
    end

    def validate_close_operation(decision)
      unless @position_manager.has_open_position?(decision.symbol)
        return ValidationResult.new(
          valid: false,
          reason: "No open position for #{decision.symbol}"
        )
      end

      ValidationResult.new(valid: true)
    end

    def enforce_risk_reward_ratio?
      Settings.risk.try(:enforce_risk_reward_ratio) != false
    end

    def min_risk_reward_ratio
      Settings.risk.try(:min_risk_reward_ratio) || DEFAULT_MIN_RISK_REWARD_RATIO
    end
  end
end
