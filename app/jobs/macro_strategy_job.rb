# frozen_string_literal: true

# Macro strategy job - high-level market analysis
#
# Runs daily at 6am (configured in config/recurring.yml) to:
# 1. Analyze weekly/daily trends
# 2. Assess macro sentiment
# 3. Generate market narrative
# 4. Set bias (bullish/bearish/neutral)
# 5. Define risk tolerance for the period
# 6. Broadcast update via ActionCable
#
class MacroStrategyJob < ApplicationJob
  queue_as :analysis

  def perform
    Rails.logger.info "[MacroStrategy] Starting macro analysis..."

    agent = Reasoning::HighLevelAgent.new
    strategy = agent.analyze

    if strategy
      Rails.logger.info "[MacroStrategy] Created strategy: #{strategy.bias} bias, " \
                        "risk tolerance: #{strategy.risk_tolerance}"
      # Broadcast new strategy via ActionCable
      DashboardChannel.broadcast_macro_strategy(strategy)
    else
      Rails.logger.warn "[MacroStrategy] Failed to create strategy (API error)"
    end

    Rails.logger.info "[MacroStrategy] Macro analysis complete"
    strategy
  end
end
