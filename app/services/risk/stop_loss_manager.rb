# frozen_string_literal: true

module Risk
  # Monitors positions and triggers stop-loss/take-profit orders
  #
  # This service runs periodically (via RiskMonitoringJob) to:
  # - Check all open positions against current prices
  # - Identify positions where SL/TP should trigger
  # - Create close decisions and execute them as market orders
  #
  # @example
  #   manager = Risk::StopLossManager.new
  #   results = manager.check_all_positions
  #   # => { triggered: [...], checked: 5, skipped: 1 }
  #
  class StopLossManager
    def initialize(client: nil, order_executor: nil)
      @client = client || Execution::HyperliquidClient.new
      @order_executor = order_executor || Execution::OrderExecutor.new
      @logger = Rails.logger
    end

    # Check all open positions and trigger SL/TP if needed
    # @return [Hash] Results summary
    def check_all_positions
      results = { triggered: [], checked: 0, skipped: 0 }
      prices = fetch_current_prices

      Position.open.find_each do |position|
        current_price = prices[position.symbol]&.to_d

        unless current_price
          @logger.warn "[StopLossManager] No price for #{position.symbol}"
          results[:skipped] += 1
          next
        end

        # Skip positions without SL/TP
        unless position.has_stop_loss? || position.has_take_profit?
          results[:skipped] += 1
          next
        end

        results[:checked] += 1

        # Update current price
        position.update_current_price!(current_price)

        # Check if SL/TP triggered
        trigger = check_position(position, current_price: current_price)
        next unless trigger

        # Execute close order
        trigger_result = execute_trigger(position, trigger, current_price)
        results[:triggered] << trigger_result if trigger_result
      end

      log_results(results)
      results
    end

    # Check if a position's SL or TP is triggered
    # @param position [Position] Position to check
    # @param current_price [Numeric] Current market price
    # @return [Symbol, nil] :stop_loss, :take_profit, or nil
    def check_position(position, current_price:)
      if position.stop_loss_triggered?(current_price)
        :stop_loss
      elsif position.take_profit_triggered?(current_price)
        :take_profit
      end
    end

    private

    def fetch_current_prices
      @client.all_mids
    rescue StandardError => e
      @logger.error "[StopLossManager] Failed to fetch prices: #{e.message}"
      {}
    end

    def execute_trigger(position, trigger, current_price)
      @logger.info "[StopLossManager] Triggering #{trigger} for #{position.symbol} at #{current_price}"

      # Create close decision
      decision = create_close_decision(position, trigger, current_price)

      # Execute via order executor (uses market order)
      order = @order_executor.execute(decision)

      if order
        close_reason = trigger == :stop_loss ? "sl_triggered" : "tp_triggered"
        position.close!(reason: close_reason)

        log_trigger(position, trigger, current_price)

        {
          position_id: position.id,
          symbol: position.symbol,
          trigger: trigger.to_s,
          price: current_price.to_f,
          order_id: order.id
        }
      end
    rescue StandardError => e
      @logger.error "[StopLossManager] Failed to execute #{trigger} for #{position.symbol}: #{e.message}"
      nil
    end

    def create_close_decision(position, trigger, current_price)
      TradingDecision.create!(
        symbol: position.symbol,
        operation: "close",
        direction: position.direction,
        confidence: 1.0, # Automated SL/TP has 100% confidence
        status: "approved",
        parsed_decision: {
          "operation" => "close",
          "symbol" => position.symbol,
          "trigger" => trigger.to_s,
          "trigger_price" => current_price.to_f,
          "reasoning" => "Automated #{trigger} trigger at #{current_price}"
        },
        llm_response: { automated: true, trigger: trigger.to_s }
      )
    end

    def log_trigger(position, trigger, price)
      ExecutionLog.create!(
        loggable: position,
        action: "risk_trigger",
        status: "success",
        executed_at: Time.current,
        request_payload: {
          trigger: trigger.to_s,
          stop_loss_price: position.stop_loss_price,
          take_profit_price: position.take_profit_price
        },
        response_payload: {
          trigger_price: price.to_f,
          position_closed: true
        }
      )
    end

    def log_results(results)
      if results[:triggered].any?
        @logger.info "[StopLossManager] Triggered #{results[:triggered].size} SL/TP orders"
      else
        @logger.debug "[StopLossManager] Checked #{results[:checked]} positions, no triggers"
      end
    end
  end
end
