# frozen_string_literal: true

module Reasoning
  # Low-level trade execution agent using Claude AI
  #
  # Runs every 5 minutes to analyze current market conditions
  # and make specific trading decisions.
  #
  class LowLevelAgent
    # Limits for context data included in prompts
    RECENT_NEWS_LIMIT = 5
    WHALE_ALERTS_LIMIT = 5

    def self.max_tokens = Settings.llm.low_level.max_tokens
    def self.temperature = Settings.llm.low_level.temperature

    SYSTEM_PROMPT = <<~PROMPT
      # Financial analysis of the crypto market

      ## Role
      You are a cryptocurrency trade execution specialist for an autonomous trading system.
      Your role is to make specific trading decisions based on current market conditions.
      It is extremely important to provide accurate and decisive guidance because the savings of many people depend on these decisions.

      ## Position Awareness
      You will receive information about whether a position already exists for this symbol.
      - If NO position exists (has_position: false): You can only choose "open" or "hold"
      - If a position EXISTS (has_position: true): You can choose "close" or "hold" (NOT "open")

      Decision logic:
      - NO position + bullish signal aligned with macro bias = "open" long
      - NO position + bearish signal aligned with macro bias = "open" short
      - NO position + unclear signals = "hold" (wait for better setup)
      - HAS position + target reached OR stop-loss near OR trend reversal = "close"
      - HAS position + trend continues in favorable direction = "hold"

      ## Input Weighting System
      You will receive data with assigned weights indicating their importance in your decision:
      - TECHNICAL (weight: 0.50) - Technical indicators (EMA, RSI, MACD, Pivots) are your PRIMARY signal. These are proven and based on actual price action.
      - SENTIMENT (weight: 0.25) - Market sentiment (Fear & Greed, news) provides confirmation or contrarian signals.
      - FORECAST (weight: 0.15) - Price predictions offer supplementary context but use with caution in volatile markets.
      - WHALE_ALERTS (weight: 0.10) - Large capital movements indicate smart money positioning.

      When data sources conflict, weight your decision according to these priorities.
      If forecast data is unavailable, redistribute its weight to other available sources.

      ## Decision Framework
      1. Check CURRENT POSITION STATUS first - this determines available operations
      2. Start with TECHNICAL indicators as primary direction indicator (EMA trends, RSI, MACD)
      3. Confirm with SENTIMENT data (Fear & Greed, news)
      4. Consider FORECAST predictions as supplementary context
      5. Factor in WHALE_ALERTS for potential sudden moves
      6. Set appropriate stop-loss and take-profit levels (for open operations)

      ## Output JSON schema for OPEN action (only when NO position exists):
      {
        "operation": "open",
        "symbol": "BTC" | "ETH" | "SOL" | "BNB",
        "direction": "long" | "short",
        "leverage": integer (1-10),
        "target_position": number (0.01 to 0.05),
        "stop_loss": number (price level),
        "take_profit": number (price level),
        "confidence": number (0.6 to 1.0),
        "reasoning": "string - concise explanation referencing weighted inputs"
      }

      ## Output JSON schema for CLOSE action (only when position EXISTS):
      {
        "operation": "close",
        "symbol": "BTC" | "ETH" | "SOL" | "BNB",
        "confidence": number (0.6 to 1.0),
        "reasoning": "string - explanation for closing (e.g., take profit, stop loss, trend reversal)"
      }

      ## Output JSON schema for HOLD action:
      {
        "operation": "hold",
        "symbol": "BTC" | "ETH" | "SOL" | "BNB",
        "confidence": number (0.0 to 1.0),
        "reasoning": "string - explanation for not trading"
      }

      ## Rules:
      - Check if a position exists FIRST before deciding on operation
      - If NO position: Only "open" or "hold" are valid operations
      - If position EXISTS: Only "close" or "hold" are valid (cannot open another position)
      - ONLY suggest "open" if you see a clear opportunity aligned with macro bias AND no position exists
      - "hold" is the default when conditions are unclear or no edge exists
      - "close" should be used when:
        - Take-profit target is approaching (within 2%)
        - Stop-loss is at risk (price moving against position)
        - Trend has reversed against the position direction
        - Market conditions have significantly changed
      - Confidence < 0.6 should result in "hold"
      - Stop-loss is REQUIRED for any "open" operation
      - Respect max leverage from risk parameters
      - Consider risk/reward ratio (aim for at least 2:1)
      - IMPORTANT: You must respond ONLY with valid JSON. No explanations outside the JSON.
    PROMPT

    def initialize
      @client = LLM::Client.new(
        max_tokens: self.class.max_tokens,
        temperature: self.class.temperature
      )
      @logger = Rails.logger
    end

    # Make trading decision for a specific symbol
    # @param symbol [String] Asset symbol (BTC, ETH, etc.)
    # @param macro_strategy [MacroStrategy, nil] Current macro strategy
    # @return [TradingDecision] Created trading decision record
    def decide(symbol:, macro_strategy: nil)
      @logger.info "[LowLevelAgent] Analyzing #{symbol}..."

      context_assembler = ContextAssembler.new(symbol: symbol)
      context = context_assembler.for_trading(macro_strategy: macro_strategy)
      user_prompt = build_user_prompt(context)

      response = call_llm(user_prompt)
      parsed = DecisionParser.parse_trading_decision(response)

      create_decision(symbol, parsed, context, response, macro_strategy)
    rescue LLM::RateLimitError => e
      @logger.warn "[LowLevelAgent] Rate limited for #{symbol}: #{e.message}"
      create_error_decision(symbol, "Rate limited - holding", macro_strategy)
    rescue LLM::APIError, LLM::ConfigurationError, Faraday::Error => e
      @logger.error "[LowLevelAgent] API error for #{symbol}: #{e.message}"
      create_error_decision(symbol, e.message, macro_strategy)
    rescue StandardError => e
      @logger.error "[LowLevelAgent] Error for #{symbol}: #{e.message}"
      create_error_decision(symbol, e.message, macro_strategy)
    end

    # Analyze all configured assets
    # @param macro_strategy [MacroStrategy, nil] Current macro strategy
    # @return [Array<TradingDecision>] Array of decisions for each asset
    def decide_all(macro_strategy: nil)
      Settings.assets.to_a.map do |symbol|
        decide(symbol: symbol, macro_strategy: macro_strategy)
      end
    end

    private

    def build_user_prompt(context)
      weights = context[:weights] || default_weights
      <<~PROMPT
        Make a trading decision for #{context[:symbol]} based on the following data:

        ## Current Time
        #{context[:timestamp]}

        ## Current Position Status
        #{format_position(context[:current_position])}

        ## Input Weights (prioritize accordingly)
        #{format_weights(weights)}

        ---

        ## [FORECAST] Price Predictions (weight: #{weights[:forecast]})
        #{format_forecast(context[:forecast])}

        ---

        ## [SENTIMENT] Market Sentiment (weight: #{weights[:sentiment]})
        - Fear & Greed Index: #{context.dig(:sentiment, :fear_greed_value)} (#{context.dig(:sentiment, :fear_greed_classification)})
        #{format_news(context[:news])}

        ---

        ## [TECHNICAL] Technical Analysis (weight: #{weights[:technical]})
        Current Price: $#{context.dig(:market_data, :price)} (24h: #{context.dig(:market_data, :price_change_pct_24h)}%)

        Indicators:
        - EMA-20: $#{format_number(context.dig(:technical_indicators, :ema_20))}
        - EMA-50: $#{format_number(context.dig(:technical_indicators, :ema_50))}
        - RSI(14): #{format_number(context.dig(:technical_indicators, :rsi_14))}
        - MACD: #{format_macd(context.dig(:technical_indicators, :macd))}
        - Pivot Points: #{format_pivots(context.dig(:technical_indicators, :pivot_points))}

        Signals:
        - RSI Signal: #{context.dig(:technical_indicators, :signals, :rsi)}
        - MACD Signal: #{context.dig(:technical_indicators, :signals, :macd)}
        - Above EMA-20: #{context.dig(:technical_indicators, :signals, :above_ema_20)}
        - Above EMA-50: #{context.dig(:technical_indicators, :signals, :above_ema_50)}

        Recent Action:
        - Trend: #{context.dig(:recent_price_action, :trend)}
        - 24h Range: $#{context.dig(:recent_price_action, :low)} - $#{context.dig(:recent_price_action, :high)}

        ---

        ## [WHALE_ALERTS] Large Capital Movements (weight: #{weights[:whale_alerts]})
        #{format_whale_alerts(context[:whale_alerts])}

        ---

        ## Macro Strategy
        #{format_macro_context(context[:macro_context])}

        ## Risk Parameters
        - Max Position: #{(context.dig(:risk_parameters, :max_position_size) || 0.05) * 100}% of capital
        - Max Leverage: #{context.dig(:risk_parameters, :max_leverage) || 10}x
        - Min Confidence: #{(context.dig(:risk_parameters, :min_confidence) || 0.6) * 100}%

        Provide your trading decision in JSON format, weighing inputs according to their assigned weights.
      PROMPT
    end

    def default_weights
      {
        forecast: Settings.weights.forecast,
        sentiment: Settings.weights.sentiment,
        technical: Settings.weights.technical,
        whale_alerts: Settings.weights.whale_alerts
      }
    end

    def format_weights(weights)
      weights.map { |k, v| "- #{k.to_s.upcase}: #{v}" }.join("\n")
    end

    def format_position(position)
      return "NO POSITION - You can OPEN a new position or HOLD" unless position&.dig(:has_position)

      <<~POS.strip
        ACTIVE #{position[:direction].upcase} POSITION:
        - Size: #{position[:size]}
        - Entry Price: $#{format_number(position[:entry_price])}
        - Current Price: $#{format_number(position[:current_price])}
        - Unrealized PnL: $#{format_number(position[:unrealized_pnl])} (#{format_number(position[:pnl_percent])}%)
        - Leverage: #{position[:leverage]}x
        - Stop Loss: #{position[:stop_loss_price] ? "$#{format_number(position[:stop_loss_price])}" : "Not set"}
        - Take Profit: #{position[:take_profit_price] ? "$#{format_number(position[:take_profit_price])}" : "Not set"}
        - Opened: #{position[:opened_at]}

        ACTION OPTIONS: You can CLOSE this position or HOLD (cannot OPEN another)
      POS
    end

    def format_forecast(forecast)
      return "No forecast data available - redistribute weight to other signals" unless forecast

      lines = []
      forecast.each do |timeframe, data|
        lines << "- #{timeframe}: Current $#{format_number(data[:current_price])} → Predicted $#{format_number(data[:predicted_price])} (#{data[:direction]})"
      end
      lines.join("\n")
    end

    def format_news(news)
      return "" unless news&.any?

      lines = [ "\nRecent News:" ]
      news.first(RECENT_NEWS_LIMIT).each do |item|
        lines << "- #{item[:title]}"
      end
      lines.join("\n")
    end

    def format_whale_alerts(alerts)
      return "No recent whale alerts" unless alerts&.any?

      lines = []
      alerts.first(WHALE_ALERTS_LIMIT).each do |alert|
        lines << "- #{alert[:action]}: #{alert[:amount]} (#{alert[:usd_value]})"
      end
      lines.join("\n")
    end

    def format_number(value)
      return "N/A" unless value

      value.respond_to?(:round) ? value.round(2) : value
    end

    def format_macd(macd)
      return "N/A" unless macd

      line = macd["macd"] || macd[:macd]
      signal = macd["signal"] || macd[:signal]
      histogram = macd["histogram"] || macd[:histogram]

      "Line: #{format_number(line)}, Signal: #{format_number(signal)}, Histogram: #{format_number(histogram)}"
    end

    def format_pivots(pivots)
      return "N/A" unless pivots

      pp = pivots["pp"] || pivots[:pp]
      r1 = pivots["r1"] || pivots[:r1]
      s1 = pivots["s1"] || pivots[:s1]

      "PP: $#{format_number(pp)}, R1: $#{format_number(r1)}, S1: $#{format_number(s1)}"
    end

    def format_macro_context(context)
      return "Not available - using default neutral stance" unless context[:available]

      <<~MACRO
        - Bias: #{context[:bias]&.upcase}
        - Risk Tolerance: #{((context[:risk_tolerance] || 0.5) * 100).round}%
        - Narrative: #{context[:market_narrative]}
      MACRO
    end

    def call_llm(user_prompt)
      @logger.info "[LowLevelAgent] Calling LLM API (#{@client.provider})..."

      response = @client.chat(
        system_prompt: SYSTEM_PROMPT,
        user_prompt: user_prompt
      )

      @logger.info "[LowLevelAgent] Received response"
      response
    end

    def create_decision(symbol, parsed, context, raw_response, macro_strategy)
      if parsed[:valid]
        data = parsed[:data]
        TradingDecision.create!(
          macro_strategy: macro_strategy,
          symbol: symbol,
          context_sent: context,
          llm_response: { "raw" => raw_response, "parsed" => data },
          parsed_decision: stringify_keys(data),
          operation: data[:operation],
          direction: data[:direction],
          confidence: data[:confidence],
          status: "pending",
          llm_model: @client.model
        )
      else
        @logger.warn "[LowLevelAgent] Invalid response for #{symbol}: #{parsed[:errors].join(', ')}"
        TradingDecision.create!(
          macro_strategy: macro_strategy,
          symbol: symbol,
          context_sent: context,
          llm_response: { "raw" => raw_response, "errors" => parsed[:errors] },
          parsed_decision: { "operation" => "hold", "reasoning" => "Invalid LLM response" },
          operation: "hold",
          confidence: 0.0,
          status: "rejected",
          rejection_reason: "Invalid LLM response: #{parsed[:errors].join(', ')}",
          llm_model: @client.model
        )
      end
    end

    def create_error_decision(symbol, error_message, macro_strategy)
      TradingDecision.create!(
        macro_strategy: macro_strategy,
        symbol: symbol,
        context_sent: {},
        llm_response: { "error" => error_message },
        parsed_decision: { "operation" => "hold", "reasoning" => "Error during analysis" },
        operation: "hold",
        confidence: 0.0,
        status: "rejected",
        rejection_reason: error_message,
        llm_model: @client.model
      )
    end

    # Convert symbol keys to string keys for JSONB storage
    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
