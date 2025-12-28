# frozen_string_literal: true

module LLM
  # Base error class for all LLM-related errors
  #
  # Provides a unified error hierarchy that abstracts provider-specific
  # exceptions, allowing the application to handle errors consistently
  # regardless of the underlying LLM provider (Anthropic, Gemini, Ollama).
  #
  class Error < StandardError
    # @return [Object, nil] The original exception from the LLM provider
    attr_reader :original_error

    # @param message [String] The error message
    # @param original_error [Exception, nil] The original provider exception
    def initialize(message = nil, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end

  # Raised when the LLM provider returns a rate limit error (HTTP 429)
  #
  # This typically indicates too many requests have been made in a short
  # period. Callers should implement backoff/retry logic when catching this.
  #
  class RateLimitError < Error; end

  # Raised when the LLM provider returns an API error
  #
  # This covers authentication failures, invalid requests, server errors,
  # and other API-related issues that are not rate limiting.
  #
  class APIError < Error; end

  # Raised when the LLM client is misconfigured
  #
  # This includes missing API keys, invalid provider settings,
  # or unsupported provider selections.
  #
  class ConfigurationError < Error; end

  # Raised when the LLM response cannot be parsed or is empty
  #
  # This indicates the provider returned a response but the content
  # could not be extracted or was malformed.
  #
  class InvalidResponseError < Error; end
end
