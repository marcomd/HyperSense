# frozen_string_literal: true

require "dry/validation"
require "oj"

module Reasoning
  # Parses and validates LLM JSON responses using dry-validation
  #
  # Handles:
  # - JSON parsing errors
  # - Schema validation
  # - Markdown code block extraction
  # - Type coercion
  #
  class DecisionParser
    VALID_SYMBOLS = %w[BTC ETH SOL BNB].freeze

    # Validation schema for trading decisions
    class TradingDecisionSchema < Dry::Validation::Contract
      params do
        required(:operation).filled(:string)
        required(:symbol).filled(:string)
        required(:confidence).filled(:decimal)
        required(:reasoning).filled(:string)
        optional(:direction).maybe(:string)
        optional(:leverage).maybe(:integer)
        optional(:target_position).maybe(:decimal)
        optional(:stop_loss).maybe(:decimal)
        optional(:take_profit).maybe(:decimal)
      end

      rule(:operation) do
        key.failure("must be one of: open, close, hold") unless %w[open close hold].include?(value)
      end

      rule(:symbol) do
        key.failure("must be one of: #{VALID_SYMBOLS.join(', ')}") unless VALID_SYMBOLS.include?(value)
      end

      rule(:confidence) do
        key.failure("must be between 0 and 1") unless value >= 0 && value <= 1
      end

      rule(:direction) do
        if values[:direction] && !%w[long short].include?(values[:direction])
          key.failure("must be one of: long, short")
        end
      end

      rule(:leverage) do
        if values[:leverage] && (values[:leverage] < 1 || values[:leverage] > 10)
          key.failure("must be between 1 and 10")
        end
      end

      # Conditional validations for open operation
      rule(:direction, :operation) do
        if values[:operation] == "open" && values[:direction].nil?
          key(:direction).failure("is required when opening a position")
        end
      end

      rule(:stop_loss, :operation) do
        if values[:operation] == "open" && values[:stop_loss].nil?
          key(:stop_loss).failure("is required when opening a position")
        end
      end

      rule(:leverage, :operation) do
        if values[:operation] == "open" && values[:leverage].nil?
          key(:leverage).failure("is required when opening a position")
        end
      end
    end

    # Validation schema for macro strategy
    class MacroStrategySchema < Dry::Validation::Contract
      params do
        required(:market_narrative).filled(:string)
        required(:bias).filled(:string)
        required(:risk_tolerance).filled(:decimal)
        required(:key_levels).value(:hash)  # Allow empty hash
        required(:reasoning).filled(:string)
      end

      rule(:market_narrative) do
        key.failure("must be at least 10 characters") if value.length < 10
      end

      rule(:bias) do
        key.failure("must be one of: bullish, bearish, neutral") unless %w[bullish bearish neutral].include?(value)
      end

      rule(:risk_tolerance) do
        key.failure("must be between 0 and 1") unless value >= 0 && value <= 1
      end
    end

    class << self
      # Parse and validate trading decision response
      # @param response [String] Raw LLM JSON response
      # @return [Hash] { valid: Boolean, data: Hash, errors: Array<String> }
      def parse_trading_decision(response)
        json = extract_json(response)
        return invalid_result([ "Failed to parse JSON from response" ]) unless json

        schema = TradingDecisionSchema.new
        result = schema.call(json)

        if result.success?
          { valid: true, data: result.to_h, errors: [] }
        else
          { valid: false, data: json, errors: format_errors(result.errors) }
        end
      rescue StandardError => e
        Rails.logger.error "[DecisionParser] Parse error: #{e.message}"
        invalid_result([ "Parse error: #{e.message}" ])
      end

      # Parse and validate macro strategy response
      # @param response [String] Raw LLM JSON response
      # @return [Hash] { valid: Boolean, data: Hash, errors: Array<String> }
      def parse_macro_strategy(response)
        json = extract_json(response)
        return invalid_result([ "Failed to parse JSON from response" ]) unless json

        schema = MacroStrategySchema.new
        result = schema.call(json)

        if result.success?
          { valid: true, data: result.to_h, errors: [] }
        else
          { valid: false, data: json, errors: format_errors(result.errors) }
        end
      rescue StandardError => e
        Rails.logger.error "[DecisionParser] Parse error: #{e.message}"
        invalid_result([ "Parse error: #{e.message}" ])
      end

      private

      # Extract JSON from LLM response (handles markdown code blocks and surrounding text)
      #
      # Attempts multiple strategies to extract valid JSON:
      # 1. Direct parse (cleanest case - response is pure JSON)
      # 2. Markdown code block extraction (```json ... ```)
      # 3. Regex extraction of JSON object from surrounding text
      #
      # @param response [String] Raw response from LLM
      # @return [Hash, nil] Parsed JSON hash or nil if extraction fails
      def extract_json(response)
        return nil if response.nil? || response.empty?

        text = response.to_s.strip

        # Strategy 1: Try direct parse (cleanest case)
        begin
          return Oj.load(text, symbol_keys: false, mode: :compat)
        rescue Oj::ParseError, EncodingError
          # Fall through to other strategies
        end

        # Strategy 2: Remove markdown code block if present
        if text.include?("```")
          # Extract content between code fences
          code_block_match = text.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m)
          if code_block_match
            begin
              return Oj.load(code_block_match[1].strip, symbol_keys: false, mode: :compat)
            rescue Oj::ParseError, EncodingError
              # Fall through to regex extraction
            end
          end
        end

        # Strategy 3: Extract JSON object from surrounding text
        # Match outermost { ... } handling up to 3 levels of nested braces
        json_match = text.match(/\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/m)
        return nil unless json_match

        Oj.load(json_match[0], symbol_keys: false, mode: :compat)
      rescue Oj::ParseError, EncodingError, JSON::ParserError => e
        Rails.logger.error "[DecisionParser] JSON parse error: #{e.message}"
        Rails.logger.error "[DecisionParser] Raw response (truncated): #{response[0..500]}"
        nil
      end

      # Create an invalid result hash
      # @param errors [Array<String>] List of error messages
      # @return [Hash] Invalid result with errors
      def invalid_result(errors)
        { valid: false, data: {}, errors: errors }
      end

      # Format dry-validation errors into string array
      # @param errors [Dry::Validation::MessageSet] Validation errors
      # @return [Array<String>] Formatted error messages
      def format_errors(errors)
        errors.to_h.flat_map do |key, messages|
          messages.map { |msg| "#{key}: #{msg}" }
        end
      end
    end
  end
end
