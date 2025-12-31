# frozen_string_literal: true

# RubyLLM Configuration
#
# Configures the ruby_llm gem based on the LLM_PROVIDER environment variable.
# Supports Anthropic, Gemini, Ollama, and OpenAI providers.
#
# Configuration is loaded from config/settings.yml which reads from ENV vars:
# - LLM_PROVIDER: anthropic, gemini, ollama, or openai
# - ANTHROPIC_API_KEY, ANTHROPIC_MODEL
# - GEMINI_API_KEY, GEMINI_MODEL
# - OLLAMA_API_BASE, OLLAMA_MODEL
# - OPENAI_API_KEY, OPENAI_MODEL
#
RubyLLM.configure do |config|
  # Anthropic configuration
  if Settings.llm.anthropic.api_key.present?
    config.anthropic_api_key = Settings.llm.anthropic.api_key
  end

  # Gemini configuration
  if Settings.llm.gemini.api_key.present?
    config.gemini_api_key = Settings.llm.gemini.api_key
  end

  # Ollama configuration (local LLM)
  if Settings.llm.ollama.api_base.present?
    config.ollama_api_base = Settings.llm.ollama.api_base
  end

  # OpenAI configuration
  if Settings.llm.openai.api_key.present?
    config.openai_api_key = Settings.llm.openai.api_key
  end

  # Connection settings
  config.request_timeout = 120  # 2 minutes for complex reasoning
  config.max_retries = 3
  config.retry_interval = 0.5
  config.retry_backoff_factor = 2

  # Logging in development
  if Rails.env.development?
    config.log_level = :info
  end
end
