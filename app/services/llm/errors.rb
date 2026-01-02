# frozen_string_literal: true

module LLM
  # Namespace module for LLM error classes
  #
  # Provides a unified error hierarchy that abstracts provider-specific
  # exceptions, allowing the application to handle errors consistently
  # regardless of the underlying LLM provider (Anthropic, Gemini, Ollama, OpenAI).
  #
  # @example Catching LLM errors
  #   begin
  #     client.chat(system_prompt: "...", user_prompt: "...")
  #   rescue LLM::Errors::RateLimitError
  #     # Handle rate limiting with backoff
  #   rescue LLM::Errors::ConfigurationError
  #     # Handle missing API keys
  #   rescue LLM::Errors::Base
  #     # Handle any other LLM error
  #   end
  #
  module Errors
    # Base error class for all LLM-related errors
    #
    # @attr_reader [Object, nil] original_error The original exception from the LLM provider
    class Base < StandardError
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
    class RateLimitError < Base; end

    # Raised when the LLM provider returns an API error
    #
    # This covers authentication failures, invalid requests, server errors,
    # and other API-related issues that are not rate limiting.
    class APIError < Base; end

    # Raised when the LLM client is misconfigured
    #
    # This includes missing API keys, invalid provider settings,
    # or unsupported provider selections.
    class ConfigurationError < Base; end

    # Raised when the LLM response cannot be parsed or is empty
    #
    # This indicates the provider returned a response but the content
    # could not be extracted or was malformed.
    class InvalidResponseError < Base; end
  end
end
