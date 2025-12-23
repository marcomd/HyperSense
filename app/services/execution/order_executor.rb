# frozen_string_literal: true

module Execution
  # Executes trading decisions by creating orders
  #
  # Supports two modes:
  # - Paper trading: Simulates order execution without real orders
  # - Live trading: Submits real orders to Hyperliquid (requires gem write operations)
  #
  # The executor validates decisions, builds orders, and manages the
  # full lifecycle from decision to executed position.
  #
  class OrderExecutor
    def initialize(client: nil, account_manager: nil, position_manager: nil)
      @client = client || HyperliquidClient.new
      @account_manager = account_manager || AccountManager.new(client: @client)
      @position_manager = position_manager || PositionManager.new(client: @client)
      @logger = Rails.logger
    end

    # Execute a trading decision
    # @param decision [TradingDecision] Decision to execute
    # @return [Order, nil] Created order or nil if rejected
    def execute(decision)
      @logger.info "[OrderExecutor] Executing decision #{decision.id} for #{decision.symbol}"

      # Validate the decision
      validation = validate_decision(decision)
      unless validation[:valid]
        reject_decision(decision, validation[:reason])
        return nil
      end

      # Get current market price
      current_price = fetch_current_price(decision.symbol)

      # Build order parameters
      order_params = build_order_params(decision, current_price)

      # Execute based on mode
      if paper_trading?
        execute_paper_trade(decision, order_params, current_price)
      else
        execute_live_trade(decision, order_params)
      end
    rescue HyperliquidClient::WriteOperationNotImplemented => e
      decision.mark_failed!(e.message)
      raise
    rescue StandardError => e
      @logger.error "[OrderExecutor] Execution failed: #{e.message}"
      decision.mark_failed!(e.message)
      log_failure(decision, order_params || {}, e.message)
      nil
    end

    private

    def paper_trading?
      Settings.trading.paper_trading
    end

    # Validate a decision before execution
    # @param decision [TradingDecision]
    # @return [Hash] { valid: Boolean, reason: String }
    def validate_decision(decision)
      # Check operation type
      if decision.operation == "hold"
        return { valid: false, reason: "Cannot execute hold operations" }
      end

      # Check confidence threshold
      min_confidence = Settings.risk.min_confidence
      if decision.confidence && decision.confidence < min_confidence
        return { valid: false, reason: "Confidence #{decision.confidence} below minimum #{min_confidence}" }
      end

      # For open operations, check for existing positions and margin
      if decision.operation == "open"
        if @position_manager.has_open_position?(decision.symbol)
          return { valid: false, reason: "Already have open position for #{decision.symbol}" }
        end

        size = decision.target_position || Settings.risk.max_position_size
        price = fetch_current_price(decision.symbol)
        leverage = decision.leverage || Settings.risk.default_leverage
        margin_required = @account_manager.margin_for_position(
          size: size, price: price, leverage: leverage
        )

        unless @account_manager.can_trade?(margin_required: margin_required)
          return { valid: false, reason: "Insufficient margin or position limit reached" }
        end
      end

      # For close operations, verify position exists
      if decision.operation == "close"
        unless @position_manager.has_open_position?(decision.symbol)
          return { valid: false, reason: "No open position for #{decision.symbol}" }
        end
      end

      { valid: true, reason: nil }
    end

    # Build order parameters from decision
    # @param decision [TradingDecision]
    # @param current_price [Numeric]
    # @return [Hash]
    def build_order_params(decision, current_price)
      if decision.operation == "close"
        position = @position_manager.get_open_position(decision.symbol)
        side = position.long? ? "sell" : "buy"
        size = position.size
      else
        side = decision.direction == "long" ? "buy" : "sell"
        size = decision.target_position || Settings.risk.max_position_size
      end

      {
        symbol: decision.symbol,
        order_type: "market",
        side: side,
        size: size,
        leverage: decision.leverage || Settings.risk.default_leverage,
        stop_loss: decision.stop_loss,
        take_profit: decision.take_profit
      }
    end

    # Execute paper trade (simulation)
    # @param decision [TradingDecision]
    # @param order_params [Hash]
    # @param current_price [Numeric]
    # @return [Order]
    def execute_paper_trade(decision, order_params, current_price)
      @logger.info "[OrderExecutor] Paper trade: #{order_params[:side]} #{order_params[:size]} #{order_params[:symbol]}"

      # Create simulated order
      order = Order.create!(
        trading_decision: decision,
        symbol: order_params[:symbol],
        order_type: order_params[:order_type],
        side: order_params[:side],
        size: order_params[:size],
        status: "pending"
      )

      # Simulate immediate fill at current price
      order.submit!("PAPER-#{SecureRandom.hex(8)}")
      order.fill!(
        filled_size: order_params[:size],
        average_price: current_price
      )

      # Create/close position based on operation
      if decision.operation == "open"
        # Calculate risk amount if SL provided
        risk_amount = nil
        if order_params[:stop_loss]
          risk_amount = Risk::RiskManager.new.calculate_risk_amount(
            size: order_params[:size],
            entry_price: current_price,
            stop_loss: order_params[:stop_loss],
            direction: decision.direction
          )
        end

        position = @position_manager.open_position(
          symbol: order_params[:symbol],
          direction: decision.direction,
          size: order_params[:size],
          entry_price: current_price,
          leverage: order_params[:leverage],
          stop_loss_price: order_params[:stop_loss],
          take_profit_price: order_params[:take_profit],
          risk_amount: risk_amount
        )
        order.update!(position: position)
      elsif decision.operation == "close"
        position = @position_manager.get_open_position(decision.symbol)
        @position_manager.close_position(position) if position
        order.update!(position: position)
      end

      # Mark decision as executed
      decision.mark_executed!

      # Log success
      log_success(order, order_params, {
        paper_trade: true,
        fill_price: current_price,
        filled_size: order_params[:size]
      })

      @logger.info "[OrderExecutor] Paper trade executed: Order ##{order.id}"
      order
    end

    # Execute live trade on Hyperliquid
    # @param decision [TradingDecision]
    # @param order_params [Hash]
    # @return [Order]
    def execute_live_trade(decision, order_params)
      @logger.info "[OrderExecutor] Live trade: #{order_params}"

      # This will raise WriteOperationNotImplemented until gem is enhanced
      @client.place_order(order_params)
    end

    def fetch_current_price(symbol)
      mids = @client.all_mids
      mids[symbol]&.to_d || raise("No price available for #{symbol}")
    end

    def reject_decision(decision, reason)
      @logger.warn "[OrderExecutor] Rejecting decision #{decision.id}: #{reason}"
      decision.reject!(reason)
    end

    def log_success(order, request, response)
      ExecutionLog.log_success!(
        loggable: order,
        action: "place_order",
        request_payload: request,
        response_payload: response
      )
    end

    def log_failure(decision, request, error)
      ExecutionLog.log_failure!(
        loggable: decision,
        action: "place_order",
        request_payload: request,
        error_message: error
      )
    end
  end
end
