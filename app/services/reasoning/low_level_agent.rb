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

    # Builds the system prompt with dynamic RSI thresholds based on active risk profile.
    # @return [String] the system prompt for the LLM
    def system_prompt
      profile = Risk::ProfileService
      rsi_oversold = profile.rsi_oversold
      rsi_overbought = profile.rsi_overbought
      rsi_pullback = profile.rsi_pullback_threshold
      rsi_bounce = profile.rsi_bounce_threshold
      min_confidence = profile.min_confidence
      min_rr_ratio = profile.min_risk_reward_ratio

      <<~PROMPT
        # Financial analysis of the crypto market

        ## Role
        You are a cryptocurrency trade execution specialist for an autonomous trading system.
        Your role is to make specific trading decisions based on current market conditions.
        It is extremely important to provide accurate and decisive guidance because the savings of many people depend on these decisions.

        ## Current Risk Profile
        #{profile.profile_description}

        ## Position Awareness
        You will receive information about whether a position already exists for this symbol.
        - If NO position exists (has_position: false): You can only choose "open" or "hold"
        - If a position EXISTS (has_position: true): You can choose "close" or "hold" (NOT "open")

        Decision logic:
        - NO position + bullish TECHNICAL signals = consider "open" long
        - NO position + bearish TECHNICAL signals = consider "open" short
        - NO position + unclear signals = "hold" (wait for better setup)
        - HAS position + CLOSE conditions met (see below) = "close"
        - HAS position + no CLOSE conditions met = "hold"

        ## Direction Independence from Macro
        The macro bias is a SUGGESTION, not a requirement. When technical signals conflict with macro:
        - Strong technical signals (RSI extreme + MACD divergence) OVERRIDE macro bias
        - You CAN and SHOULD open SHORTS during bullish macro when RSI > #{rsi_overbought} (overbought) + bearish MACD
        - You CAN and SHOULD open LONGS during bearish macro when RSI < #{rsi_oversold} (oversold) + bullish MACD
        - Technical indicators are KING - they reflect actual price action

        ## RSI Entry Filters (CRITICAL - check BEFORE opening)
        - NEVER open LONG if RSI > #{rsi_overbought} (overbought) - wait for pullback below #{rsi_pullback}
        - NEVER open SHORT if RSI < #{rsi_oversold} (oversold) - wait for bounce above #{rsi_bounce}
        - When RSI is #{rsi_pullback}-#{rsi_overbought} and opening LONG, reduce confidence by 0.15
        - When RSI is #{rsi_oversold}-#{rsi_bounce} and opening SHORT, reduce confidence by 0.15

        ## CLOSE Operation Rules (data-driven decisions using peak tracking and momentum)
        You will receive PEAK TRACKING and MOMENTUM data in the position info. Use them wisely.

        CLOSE operation is VALID when ANY of these conditions is met:

        TAKE PROFIT ZONE (profile-specific threshold):
        1. Position is marked "is_in_tp_zone: true" (within TP zone threshold)
        2. Price is within 1% of stop-loss level (is_near_sl: true)

        PROFIT PROTECTION (use peak tracking data):
        3. profit_drawdown_from_peak_pct > 30% (significant profit fade)
           Example: Position peaked at +3% profit but is now at +2% = 33% of profit lost

        MOMENTUM REVERSAL (use momentum signals):
        4. rsi_trend is "falling" AND macd_momentum is "falling" (momentum fading)
        5. rsi_divergence is "bearish" (price rising but RSI falling = reversal warning)

        STALLED POSITION:
        6. Position held 4+ hours with < 1% progress toward TP

        Do NOT close for:
        - Minor pullbacks within normal volatility (let trailing stop handle this)
        - "Feeling uncertain" without data backing
        - Small profit drawdowns (< 25%) - these are normal fluctuations

        IMPORTANT: Trailing stop will automatically protect profits once activated.
        Focus on momentum signals and divergences for early exit opportunities.
        Let the data guide you, not emotions.

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
        3. Apply RSI entry filters (no longs when overbought, no shorts when oversold)
        4. Confirm with SENTIMENT data (Fear & Greed, news)
        5. Consider FORECAST predictions as supplementary context
        6. Factor in WHALE_ALERTS for potential sudden moves
        7. Set appropriate stop-loss and take-profit levels (for open operations)

        ## Output JSON schema for OPEN action (only when NO position exists):
        {
          "operation": "open",
          "symbol": "BTC" | "ETH" | "SOL" | "BNB",
          "direction": "long" | "short",
          "leverage": integer (1-10),
          "target_position": number (0.01 to 0.05),
          "stop_loss": number (price level),
          "take_profit": number (price level),
          "confidence": number (#{min_confidence} to 1.0),
          "reasoning": "string - concise explanation referencing weighted inputs"
        }

        ## Output JSON schema for CLOSE action (only when position EXISTS):
        {
          "operation": "close",
          "symbol": "BTC" | "ETH" | "SOL" | "BNB",
          "confidence": number (#{min_confidence} to 1.0),
          "reasoning": "string - MUST cite specific close condition met (TP near, SL near, or confirmed reversal)"
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
        - ONLY suggest "open" if technical signals are clear AND RSI allows entry
        - "hold" is the default when conditions are unclear or no edge exists
        - "close" should ONLY be used when close conditions above are met
        - Confidence < #{min_confidence} should result in "hold"
        - Stop-loss is REQUIRED for any "open" operation
        - Respect max leverage from risk parameters
        - Consider risk/reward ratio (aim for at least #{min_rr_ratio}:1)
        - IMPORTANT: You must respond ONLY with valid JSON. No explanations outside the JSON.
      PROMPT
    end

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
    rescue LLM::Errors::RateLimitError => e
      @logger.warn "[LowLevelAgent] Rate limited for #{symbol}: #{e.message}"
      create_error_decision(symbol, "Rate limited - holding", macro_strategy)
    rescue LLM::Errors::APIError, LLM::Errors::ConfigurationError, Faraday::Error => e
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
        - EMA-100: $#{format_number(context.dig(:technical_indicators, :ema_100))}
        - EMA-200: $#{format_number(context.dig(:technical_indicators, :ema_200))} (long-term trend)
        - RSI(14): #{format_number(context.dig(:technical_indicators, :rsi_14))}
        - MACD: #{format_macd(context.dig(:technical_indicators, :macd))}
        - Pivot Points: #{format_pivots(context.dig(:technical_indicators, :pivot_points))}

        Signals:
        - RSI Signal: #{context.dig(:technical_indicators, :signals, :rsi)}
        - MACD Signal: #{context.dig(:technical_indicators, :signals, :macd)}
        - Above EMA-20: #{context.dig(:technical_indicators, :signals, :above_ema_20)}
        - Above EMA-50: #{context.dig(:technical_indicators, :signals, :above_ema_50)}
        - Above EMA-200: #{context.dig(:technical_indicators, :signals, :above_ema_200)} (bull/bear market structure)

        Recent Action:
        - Trend: #{context.dig(:recent_price_action, :trend)}
        - 24h Range: $#{context.dig(:recent_price_action, :low)} - $#{context.dig(:recent_price_action, :high)}

        ---

        ## [WHALE_ALERTS] Large Capital Movements (weight: #{weights[:whale_alerts]})
        #{format_whale_alerts(context[:whale_alerts])}

        ---

        ## Macro Strategy
        #{format_macro_context(context[:macro_context])}

        ## Momentum Analysis (for exit decisions)
        #{format_momentum(context[:momentum_signals])}

        ## Risk Parameters
        - Max Position: #{(context.dig(:risk_parameters, :max_position_size) || 0.05) * 100}% of capital
        - Max Leverage: #{context.dig(:risk_parameters, :max_leverage) || 10}x
        - Min Confidence: #{(context.dig(:risk_parameters, :min_confidence) || 0.6) * 100}%
        - TP Zone Threshold: #{(context.dig(:risk_parameters, :tp_zone_pct) || 0.02) * 100}%
        - Trailing Stop: #{context.dig(:risk_parameters, :trailing_stop_enabled) ? "Enabled" : "Disabled"}

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

      profile = Risk::ProfileService
      age_str = format_position_age(position[:position_age_minutes])
      tp_dist = position[:pct_to_take_profit] ? "#{position[:pct_to_take_profit]}%" : "N/A"
      sl_dist = position[:pct_to_stop_loss] ? "#{position[:pct_to_stop_loss]}%" : "N/A"
      tp_zone = position[:is_in_tp_zone] ? "YES - CONSIDER CLOSING" : "No"
      near_sl = position[:is_near_sl] ? "YES - CAUTION" : "No"

      # Peak tracking info
      peak_info = if position[:peak_price]
        "Peak: $#{format_number(position[:peak_price])} (#{position[:minutes_since_peak] || 0} min ago)"
      else
        "Peak: Not yet tracked"
      end

      # Profit drawdown alert
      profit_drawdown = position[:profit_drawdown_from_peak_pct] || 0
      profit_alert = if profit_drawdown > (profile.profit_drawdown_alert_pct * 100)
        " ** PROFIT FADING - #{profit_drawdown.round(1)}% of peak profit lost **"
      else
        ""
      end

      # Trailing stop status
      trailing = if position[:trailing_stop_active]
        "ACTIVE (original SL: $#{format_number(position[:original_stop_loss_price])})"
      else
        "Not activated"
      end

      <<~POS.strip
        ACTIVE #{position[:direction].upcase} POSITION:
        - Entry: $#{format_number(position[:entry_price])} | Current: $#{format_number(position[:current_price])}
        - Unrealized PnL: $#{format_number(position[:unrealized_pnl])} (#{format_number(position[:pnl_percent])}%)#{profit_alert}
        - Leverage: #{position[:leverage]}x | Age: #{age_str}

        TARGETS:
        - Stop Loss: $#{format_number(position[:stop_loss_price])} (#{sl_dist} away)
        - Take Profit: $#{format_number(position[:take_profit_price])} (#{tp_dist} away)
        - In TP Zone (#{(profile.tp_zone_pct * 100).round(1)}% threshold): #{tp_zone}
        - Near SL: #{near_sl}

        PEAK TRACKING:
        - #{peak_info}
        - Drawdown from Peak: #{position[:drawdown_from_peak_pct] || 0}%
        - Profit Drawdown: #{profit_drawdown.round(1)}% of peak profit lost
        - Trailing Stop: #{trailing}

        ACTION OPTIONS: You can CLOSE this position or HOLD
      POS
    end

    def format_position_age(minutes)
      return "Unknown" unless minutes

      if minutes < 60
        "#{minutes} min"
      elsif minutes < 1440
        "#{(minutes / 60.0).round(1)} hours"
      else
        "#{(minutes / 1440.0).round(1)} days"
      end
    end

    def format_momentum(signals)
      return "No momentum data available" unless signals&.any?

      rsi_trend = signals[:rsi_trend] || "unknown"
      macd_momentum = signals[:macd_momentum] || "unknown"
      price_trend = signals[:price_trend] || "unknown"
      divergence = signals[:rsi_divergence] || "none"

      divergence_warning = case divergence
      when "bearish"
        " ** BEARISH DIVERGENCE - price up but RSI down, reversal warning! **"
      when "bullish"
        " ** BULLISH DIVERGENCE - price down but RSI up, bounce possible! **"
      else
        ""
      end

      <<~MOM.strip
        - RSI Trend: #{rsi_trend} (is RSI rising, falling, or flat?)
        - MACD Momentum: #{macd_momentum} (is momentum accelerating or decelerating?)
        - Price Trend: #{price_trend}
        - RSI Divergence: #{divergence}#{divergence_warning}
      MOM
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
        system_prompt: system_prompt,
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
          llm_model: @client.model,
          risk_profile_name: RiskProfile.current_name
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
          llm_model: @client.model,
          risk_profile_name: RiskProfile.current_name
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
        llm_model: @client.model,
        risk_profile_name: RiskProfile.current_name
      )
    end

    # Convert symbol keys to string keys for JSONB storage
    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
