# frozen_string_literal: true

module Costs
  # Estimates LLM costs based on call counts and max_tokens settings
  #
  # Since actual token usage is not tracked, costs are estimated using:
  # - Number of LLM calls (from TradingDecision and MacroStrategy records)
  # - Configured max_tokens for high-level and low-level agents
  # - Estimated utilization factor (70% of max_tokens on average)
  # - Input/output token ratio (3:1 for context-heavy trading prompts)
  #
  # @example Estimate costs for today
  #   calculator = Costs::LLMCostCalculator.new
  #   result = calculator.estimated_costs(since: Time.current.beginning_of_day)
  #   result[:total] # => 0.85 (USD)
  #
  class LLMCostCalculator
    # Estimated input/output token ratio (trading prompts have lots of context)
    INPUT_OUTPUT_RATIO = 3.0

    # Estimated utilization of max_tokens (typically responses don't use full limit)
    UTILIZATION_FACTOR = 0.70

    # Decimal precision for cost calculations
    COST_PRECISION = 4

    # Calculate estimated LLM costs for a time period
    # @param since [Time, nil] Start of period (nil = all time)
    # @return [Hash] Cost breakdown by agent type
    def estimated_costs(since: nil)
      provider = current_provider
      model = current_model
      pricing = model_pricing(provider, model)

      # Count LLM calls
      macro_calls = count_macro_calls(since: since)
      trading_calls = count_trading_calls(since: since)

      # Estimate token usage
      macro_tokens = estimate_macro_tokens(macro_calls)
      trading_tokens = estimate_trading_tokens(trading_calls)

      # Calculate costs
      macro_cost = calculate_cost(macro_tokens, pricing)
      trading_cost = calculate_cost(trading_tokens, pricing)

      {
        provider: provider,
        model: model,
        pricing: pricing,
        macro_strategy: {
          calls: macro_calls,
          estimated_input_tokens: macro_tokens[:input],
          estimated_output_tokens: macro_tokens[:output],
          cost: macro_cost.round(COST_PRECISION)
        },
        trading_decisions: {
          calls: trading_calls,
          estimated_input_tokens: trading_tokens[:input],
          estimated_output_tokens: trading_tokens[:output],
          cost: trading_cost.round(COST_PRECISION)
        },
        total_calls: macro_calls + trading_calls,
        total: (macro_cost + trading_cost).round(COST_PRECISION)
      }
    end

    # Get pricing info for current provider/model
    # @return [Hash] Current pricing configuration
    def current_pricing
      provider = current_provider
      model = current_model

      {
        provider: provider,
        model: model,
        pricing: model_pricing(provider, model)
      }
    end

    private

    # Get current LLM provider from settings
    # @return [String] Provider name (anthropic, gemini, ollama)
    def current_provider
      Settings.llm.provider.to_s
    end

    # Get current model for the provider
    # @return [String] Model name
    def current_model
      case current_provider
      when "anthropic" then Settings.llm.anthropic.model
      when "gemini" then Settings.llm.gemini.model
      when "ollama" then Settings.llm.ollama.model
      else "unknown"
      end
    end

    # Get pricing for a specific provider/model
    # @param provider [String] Provider name
    # @param model [String] Model name
    # @return [Hash] Pricing with input_per_million and output_per_million
    def model_pricing(provider, model)
      provider_settings = safe_setting_access(Settings.costs.llm, provider)
      return free_pricing if provider_settings.nil?

      model_settings = safe_setting_access(provider_settings, model)
      model_settings ||= safe_setting_access(provider_settings, "default")

      return free_pricing if model_settings.nil?

      {
        input_per_million: model_settings.input_per_million.to_f,
        output_per_million: model_settings.output_per_million.to_f
      }
    end

    # Safely access nested settings (returns nil if not found)
    # @param settings [Config::Options] Settings object
    # @param key [String] Key to access
    # @return [Config::Options, nil] Nested settings or nil
    def safe_setting_access(settings, key)
      settings.send(key)
    rescue NoMethodError
      nil
    end

    # Free pricing for local models (ollama)
    # @return [Hash] Zero-cost pricing
    def free_pricing
      { input_per_million: 0.0, output_per_million: 0.0 }
    end

    # Count macro strategy LLM calls
    # @param since [Time, nil] Start of period
    # @return [Integer] Number of macro strategy records
    def count_macro_calls(since:)
      scope = MacroStrategy.all
      scope = scope.where("created_at >= ?", since) if since
      scope.count
    end

    # Count trading decision LLM calls
    # @param since [Time, nil] Start of period
    # @return [Integer] Number of trading decision records
    def count_trading_calls(since:)
      scope = TradingDecision.all
      scope = scope.where("created_at >= ?", since) if since
      scope.count
    end

    # Estimate tokens for macro strategy calls
    # @param call_count [Integer] Number of calls
    # @return [Hash] Estimated input and output tokens
    def estimate_macro_tokens(call_count)
      max_output = Settings.llm.high_level.max_tokens
      estimated_output = (max_output * UTILIZATION_FACTOR).to_i
      estimated_input = (estimated_output * INPUT_OUTPUT_RATIO).to_i

      {
        input: estimated_input * call_count,
        output: estimated_output * call_count
      }
    end

    # Estimate tokens for trading decision calls
    # @param call_count [Integer] Number of calls
    # @return [Hash] Estimated input and output tokens
    def estimate_trading_tokens(call_count)
      max_output = Settings.llm.low_level.max_tokens
      estimated_output = (max_output * UTILIZATION_FACTOR).to_i
      estimated_input = (estimated_output * INPUT_OUTPUT_RATIO).to_i

      {
        input: estimated_input * call_count,
        output: estimated_output * call_count
      }
    end

    # Calculate cost from tokens and pricing
    # @param tokens [Hash] Input and output token counts
    # @param pricing [Hash] Pricing rates per million tokens
    # @return [Float] Total cost in USD
    def calculate_cost(tokens, pricing)
      input_cost = (tokens[:input] / 1_000_000.0) * pricing[:input_per_million]
      output_cost = (tokens[:output] / 1_000_000.0) * pricing[:output_per_million]
      input_cost + output_cost
    end
  end
end
