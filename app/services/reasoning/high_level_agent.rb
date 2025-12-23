# frozen_string_literal: true

module Reasoning
  # High-level macro strategy agent using Claude AI
  #
  # Runs daily to analyze overall market conditions and set
  # strategic direction (bias, risk tolerance) for the day.
  #
  class HighLevelAgent
    def self.model = Settings.llm.model
    def self.max_tokens = Settings.llm.high_level.max_tokens
    def self.temperature = Settings.llm.high_level.temperature

    SYSTEM_PROMPT = <<~PROMPT
      You are a senior cryptocurrency macro strategist for an autonomous trading system.
      Your role is to analyze market conditions and provide strategic guidance for the day.

      IMPORTANT: You must respond ONLY with valid JSON. No explanations outside the JSON.

      Your analysis should consider:
      1. Overall market sentiment (Fear & Greed Index)
      2. Technical trends across major assets (BTC, ETH, SOL, BNB)
      3. Support and resistance levels
      4. Risk environment

      Output JSON schema:
      {
        "market_narrative": "string - 2-3 sentence summary of current market conditions",
        "bias": "bullish" | "bearish" | "neutral",
        "risk_tolerance": number (0.0 to 1.0, where 1.0 = aggressive, 0.0 = conservative),
        "key_levels": {
          "BTC": { "support": [price1, price2], "resistance": [price1, price2] },
          "ETH": { "support": [price1, price2], "resistance": [price1, price2] },
          "SOL": { "support": [price1, price2], "resistance": [price1, price2] },
          "BNB": { "support": [price1, price2], "resistance": [price1, price2] }
        },
        "reasoning": "string - detailed reasoning for your analysis"
      }

      Guidelines for risk_tolerance:
      - 0.0-0.3: Extreme caution (high fear, uncertain conditions)
      - 0.3-0.5: Conservative (elevated risk, proceed carefully)
      - 0.5-0.7: Normal (balanced conditions)
      - 0.7-0.9: Opportunistic (favorable conditions, clear trends)
      - 0.9-1.0: Aggressive (strong conviction setups only)

      Be decisive. Neutral bias should only be used when signals genuinely conflict.
    PROMPT

    def initialize
      @client = Anthropic::Client.new(
        api_key: Settings.anthropic.api_key
      )
      @logger = Rails.logger
      @context_assembler = ContextAssembler.new
    end

    # Generate macro strategy analysis
    # @return [MacroStrategy, nil] Created macro strategy record or nil on API error
    def analyze
      @logger.info "[HighLevelAgent] Starting macro analysis..."

      context = @context_assembler.for_macro_analysis
      user_prompt = build_user_prompt(context)

      response = call_llm(user_prompt)
      parsed = DecisionParser.parse_macro_strategy(response)

      if parsed[:valid]
        create_strategy(parsed[:data], context, response)
      else
        handle_invalid_response(parsed[:errors], context, response)
      end
    rescue Anthropic::RateLimitError => e
      @logger.warn "[HighLevelAgent] Rate limited: #{e.message}"
      nil
    rescue Anthropic::Errors::APIError, Faraday::Error => e
      @logger.error "[HighLevelAgent] API error: #{e.message}"
      nil
    rescue StandardError => e
      @logger.error "[HighLevelAgent] Unexpected error: #{e.message}"
      @logger.error e.backtrace.first(5).join("\n")
      raise
    end

    private

    def build_user_prompt(context)
      <<~PROMPT
        Analyze the following market data and provide your macro strategy for today:

        ## Current Timestamp
        #{context[:timestamp]}

        ## Market Sentiment
        Fear & Greed Index: #{context.dig(:market_sentiment, :fear_greed_value)} (#{context.dig(:market_sentiment, :fear_greed_classification)})

        ## Assets Overview
        #{format_assets_overview(context[:assets_overview])}

        ## Historical Trends (#{ContextAssembler::LOOKBACK_DAYS_MACRO} days)
        #{format_historical_trends(context[:historical_trends])}

        ## Risk Parameters
        - Max Position Size: #{context.dig(:risk_parameters, :max_position_size)}
        - Max Leverage: #{context.dig(:risk_parameters, :max_leverage)}

        Provide your macro strategy in JSON format.
      PROMPT
    end

    def format_assets_overview(assets)
      return "No asset data available" if assets.nil? || assets.empty?

      assets.filter_map do |asset|
        next if asset[:market_data].empty?

        <<~ASSET
          ### #{asset[:symbol]}
          - Price: $#{asset.dig(:market_data, :price)&.round(2)}
          - 24h Change: #{asset.dig(:market_data, :price_change_pct_24h)&.round(2)}%
          - RSI(14): #{asset.dig(:technical_indicators, :rsi_14)&.round(1)}
          - MACD Signal: #{asset.dig(:technical_indicators, :signals, :macd)}
          - Above EMA-50: #{asset.dig(:technical_indicators, :signals, :above_ema_50)}
        ASSET
      end.join("\n")
    end

    def format_historical_trends(trends)
      return "No historical data available" if trends.nil? || trends.empty?

      trends.map do |symbol, data|
        "- #{symbol}: #{data[:change_pct]}% change, volatility: #{data[:volatility]}%"
      end.join("\n")
    end

    def call_llm(user_prompt)
      @logger.info "[HighLevelAgent] Calling Claude API..."

      response = @client.messages.create(
        model: self.class.model,
        max_tokens: self.class.max_tokens,
        temperature: self.class.temperature,
        system: SYSTEM_PROMPT,
        messages: [ { role: "user", content: user_prompt } ]
      )

      content = response.content.first
      raise "Empty response from LLM" unless content&.text

      @logger.info "[HighLevelAgent] Received response (#{content.text.length} chars)"
      content.text
    end

    def create_strategy(data, context, raw_response)
      strategy = MacroStrategy.create!(
        market_narrative: data[:market_narrative],
        bias: data[:bias],
        risk_tolerance: data[:risk_tolerance],
        key_levels: data[:key_levels],
        context_used: context,
        llm_response: { "raw" => raw_response, "parsed" => data },
        valid_until: Time.current + Settings.macro.refresh_interval_hours.hours
      )

      @logger.info "[HighLevelAgent] Created macro strategy: bias=#{strategy.bias}, risk=#{strategy.risk_tolerance}"
      strategy
    end

    def handle_invalid_response(errors, context, raw_response)
      @logger.error "[HighLevelAgent] Invalid LLM response: #{errors.join(', ')}"

      # Create a fallback neutral strategy with shorter validity
      MacroStrategy.create!(
        market_narrative: "Unable to parse LLM response. Defaulting to neutral stance.",
        bias: "neutral",
        risk_tolerance: 0.5,
        key_levels: {},
        context_used: context,
        llm_response: { "raw" => raw_response, "errors" => errors },
        valid_until: Time.current + 6.hours
      )
    end
  end
end
