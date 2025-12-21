# frozen_string_literal: true

# Main orchestrator for the trading cycle
#
# Coordinates the entire trading workflow:
# 1. Check/refresh macro strategy
# 2. Run low-level agent for all assets
# 3. Log decisions
# 4. (Phase 4/5) Apply risk management
# 5. (Phase 4/5) Execute approved trades
#
class TradingCycle
  def initialize
    @logger = Rails.logger
  end

  # Execute the full trading cycle
  # @return [Array<TradingDecision>] Array of decisions made
  def execute
    @logger.info "[TradingCycle] Starting execution..."

    # Step 1: Ensure we have a valid macro strategy
    ensure_macro_strategy

    # Step 2: Get current macro strategy
    macro_strategy = MacroStrategy.active
    @logger.info "[TradingCycle] Using macro strategy: #{macro_strategy&.bias || 'none'}"

    # Step 3: Run low-level agent for all assets
    decisions = run_low_level_agent(macro_strategy)

    # Step 4: Log decisions
    log_decisions(decisions)

    # Step 5: (Phase 4/5) Risk management and execution
    # approved = filter_and_approve(decisions)
    # execute_decisions(approved)

    @logger.info "[TradingCycle] Execution complete"
    decisions
  end

  private

  # Ensure we have a valid macro strategy, refresh if needed
  def ensure_macro_strategy
    return unless MacroStrategy.needs_refresh?

    @logger.info "[TradingCycle] Macro strategy needs refresh, triggering job..."
    MacroStrategyJob.perform_now
  end

  # Run low-level agent for all configured assets
  # @param macro_strategy [MacroStrategy, nil] Current macro strategy
  # @return [Array<TradingDecision>] Array of decisions
  def run_low_level_agent(macro_strategy)
    @logger.info "[TradingCycle] Running low-level agent..."

    agent = Reasoning::LowLevelAgent.new
    agent.decide_all(macro_strategy: macro_strategy)
  end

  # Log summary of decisions
  # @param decisions [Array<TradingDecision>] Decisions to log
  def log_decisions(decisions)
    decisions.each do |decision|
      @logger.info "[TradingCycle] #{decision.symbol}: #{decision.operation} " \
                   "(confidence: #{decision.confidence}, status: #{decision.status})"
    end

    actionable = decisions.select(&:actionable?)
    holds = decisions.select(&:hold?)

    @logger.info "[TradingCycle] Summary: #{actionable.size} actionable, #{holds.size} holds out of #{decisions.size} total"
  end

  # === Phase 4/5 Methods (TODO) ===

  # Filter decisions through risk management and approve valid ones
  # @param decisions [Array<TradingDecision>] Decisions to filter
  # @return [Array<TradingDecision>] Approved decisions
  def filter_and_approve(decisions)
    # TODO: Implement in Phase 5
    # decisions.select do |decision|
    #   next false unless decision.actionable?
    #   next false if decision.confidence < Settings.risk.min_confidence
    #
    #   risk_result = Risk::RiskManager.new.validate(decision, current_portfolio)
    #   if risk_result.approved?
    #     decision.approve!
    #     true
    #   else
    #     decision.reject!(risk_result.reason)
    #     false
    #   end
    # end
    []
  end

  # Execute approved decisions
  # @param approved_decisions [Array<TradingDecision>] Decisions to execute
  def execute_decisions(approved_decisions)
    # TODO: Implement in Phase 4
    # return if Settings.trading.paper_trading
    #
    # approved_decisions.each do |decision|
    #   Execution::TradeExecutor.new.execute(decision)
    # end
  end

  # Get current portfolio state
  # @return [Hash] Portfolio state (positions, capital, etc.)
  def current_portfolio
    # TODO: Implement in Phase 4
    # {
    #   positions: Position.open.to_a,
    #   available_capital: calculate_available_capital,
    #   total_exposure: calculate_total_exposure
    # }
    {}
  end
end
