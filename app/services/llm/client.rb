# frozen_string_literal: true

require_relative "errors"

module LLM
  # LLM-agnostic client wrapper for ruby_llm
  #
  # Provides a unified interface for interacting with different LLM providers
  # (Anthropic, Gemini, Ollama, OpenAI) based on the LLM_PROVIDER environment variable.
  #
  # @example Basic usage
  #   client = LLM::Client.new(max_tokens: 1500, temperature: 0.3)
  #   response = client.chat(
  #     system_prompt: "You are a helpful assistant.",
  #     user_prompt: "What is the capital of France?"
  #   )
  #   puts response # => "Paris is the capital of France."
  #
  class Client
    # Supported LLM providers
    SUPPORTED_PROVIDERS = %w[anthropic gemini ollama openai].freeze

    # @return [String] The model identifier for the current provider
    attr_reader :model

    # @return [Integer] Maximum tokens for the response
    attr_reader :max_tokens

    # @return [Float] Temperature setting for response creativity
    attr_reader :temperature

    # @return [String] The LLM provider (anthropic, gemini, ollama)
    attr_reader :provider

    # Initialize a new LLM client
    #
    # @param model [String, nil] Model identifier (defaults to provider-specific setting)
    # @param max_tokens [Integer, nil] Maximum response tokens (defaults to 1500)
    # @param temperature [Float, nil] Response temperature (defaults to 0.3)
    # @raise [LLM::ConfigurationError] If provider is not supported or not configured
    def initialize(model: nil, max_tokens: nil, temperature: nil)
      @provider = Settings.llm.provider.to_s
      validate_provider!

      @model = model || default_model
      @max_tokens = max_tokens || 1500
      @temperature = temperature || 0.3

      validate_configuration!
    end

    # Send a chat request to the LLM
    #
    # @param system_prompt [String] The system/instruction prompt
    # @param user_prompt [String] The user message
    # @return [String] The assistant's response text
    # @raise [LLM::RateLimitError] When rate limited by provider
    # @raise [LLM::APIError] When API returns an error
    # @raise [LLM::InvalidResponseError] When response cannot be parsed
    def chat(system_prompt:, user_prompt:)
      chat_instance = build_chat(system_prompt)
      response = chat_instance.ask(user_prompt)

      extract_content(response)
    rescue RubyLLM::RateLimitError => e
      raise LLM::RateLimitError.new(e.message, original_error: e)
    rescue RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError => e
      raise LLM::ConfigurationError.new("Authentication failed: #{e.message}", original_error: e)
    rescue RubyLLM::BadRequestError, RubyLLM::ServerError,
           RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError => e
      raise LLM::APIError.new(e.message, original_error: e)
    rescue RubyLLM::Error => e
      raise LLM::APIError.new("LLM error: #{e.message}", original_error: e)
    end

    private

    # Validate that the provider is supported
    #
    # @raise [LLM::ConfigurationError] If provider is not supported
    def validate_provider!
      return if SUPPORTED_PROVIDERS.include?(@provider)

      raise ConfigurationError, "Unsupported LLM provider: '#{@provider}'. " \
                                "Supported: #{SUPPORTED_PROVIDERS.join(', ')}"
    end

    # Validate provider-specific configuration
    #
    # @raise [LLM::ConfigurationError] If required settings are missing
    def validate_configuration!
      case @provider
      when "anthropic"
        validate_api_key!(Settings.llm.anthropic.api_key, "ANTHROPIC_API_KEY")
      when "gemini"
        validate_api_key!(Settings.llm.gemini.api_key, "GEMINI_API_KEY")
      when "openai"
        validate_api_key!(Settings.llm.openai.api_key, "OPENAI_API_KEY")
      when "ollama"
        # Ollama doesn't require an API key, just a running server
        nil
      end
    end

    # Validate that an API key is present
    #
    # @param key [String, nil] The API key value
    # @param env_var [String] The environment variable name for error messages
    # @raise [LLM::ConfigurationError] If key is blank
    def validate_api_key!(key, env_var)
      return if key.present?

      raise ConfigurationError, "#{env_var} is required for #{@provider} provider"
    end

    # Get the default model for the current provider
    #
    # @return [String] The default model identifier
    def default_model
      case @provider
      when "anthropic"
        Settings.llm.anthropic.model
      when "gemini"
        Settings.llm.gemini.model
      when "openai"
        Settings.llm.openai.model
      when "ollama"
        Settings.llm.ollama.model
      end
    end

    # Build a RubyLLM chat instance with configuration
    #
    # @param system_prompt [String] The system instruction
    # @return [RubyLLM::Chat] Configured chat instance
    def build_chat(system_prompt)
      RubyLLM.chat(model: @model)
             .with_instructions(system_prompt)
             .with_temperature(@temperature)
             .with_params(**provider_params)
    end

    # Returns the provider-specific parameters for max tokens
    #
    # Different providers use different parameter names:
    # - Anthropic: max_tokens (top level)
    # - OpenAI: max_tokens (top level)
    # - Ollama: max_tokens (top level, OpenAI-compatible)
    # - Gemini: generationConfig.maxOutputTokens
    #
    # @return [Hash] Provider-specific parameters
    def provider_params
      case @provider
      when "gemini"
        { generationConfig: { maxOutputTokens: @max_tokens } }
      else
        # Anthropic and Ollama use max_tokens at top level
        { max_tokens: @max_tokens }
      end
    end

    # Extract text content from the response
    #
    # @param response [RubyLLM::Message] The chat response
    # @return [String] The response text
    # @raise [LLM::InvalidResponseError] If content is empty
    def extract_content(response)
      content = response&.content
      raise InvalidResponseError, "Empty response from LLM" if content.blank?

      content
    end
  end
end
