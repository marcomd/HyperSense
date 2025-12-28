# frozen_string_literal: true

require "rails_helper"

RSpec.describe LLM::Client do
  describe "#initialize" do
    context "with default configuration (anthropic)" do
      it "creates a client with anthropic provider" do
        client = described_class.new
        expect(client.provider).to eq("anthropic")
      end

      it "uses default model from settings" do
        client = described_class.new
        expect(client.model).to eq(Settings.llm.anthropic.model)
      end

      it "uses provided max_tokens" do
        client = described_class.new(max_tokens: 1000)
        expect(client.max_tokens).to eq(1000)
      end

      it "uses provided temperature" do
        client = described_class.new(temperature: 0.5)
        expect(client.temperature).to eq(0.5)
      end

      it "allows overriding model" do
        client = described_class.new(model: "claude-opus-4")
        expect(client.model).to eq("claude-opus-4")
      end
    end

    context "with unsupported provider" do
      before do
        allow(Settings.llm).to receive(:provider).and_return("unsupported_provider")
      end

      it "raises ConfigurationError" do
        expect { described_class.new }.to raise_error(
          LLM::ConfigurationError,
          /Unsupported LLM provider: 'unsupported_provider'/
        )
      end
    end

    context "with anthropic provider and missing API key" do
      before do
        allow(Settings.llm).to receive(:provider).and_return("anthropic")
        allow(Settings.llm.anthropic).to receive(:api_key).and_return("")
      end

      it "raises ConfigurationError" do
        expect { described_class.new }.to raise_error(
          LLM::ConfigurationError,
          /ANTHROPIC_API_KEY is required/
        )
      end
    end

    context "with gemini provider and missing API key" do
      before do
        allow(Settings.llm).to receive(:provider).and_return("gemini")
        allow(Settings.llm.gemini).to receive(:api_key).and_return("")
      end

      it "raises ConfigurationError" do
        expect { described_class.new }.to raise_error(
          LLM::ConfigurationError,
          /GEMINI_API_KEY is required/
        )
      end
    end

    context "with ollama provider" do
      before do
        allow(Settings.llm).to receive(:provider).and_return("ollama")
      end

      it "does not require API key" do
        expect { described_class.new }.not_to raise_error
      end

      it "uses ollama model from settings" do
        client = described_class.new
        expect(client.model).to eq(Settings.llm.ollama.model)
      end
    end
  end

  describe "#chat" do
    let(:client) { described_class.new(max_tokens: 1000, temperature: 0.3) }
    let(:system_prompt) { "You are a helpful assistant." }
    let(:user_prompt) { "Hello, world!" }

    context "with successful response" do
      let(:mock_response) { double("response", content: "Hello! How can I help you?") }
      let(:mock_chat) { double("chat") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_params).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "returns the response content" do
        result = client.chat(system_prompt: system_prompt, user_prompt: user_prompt)
        expect(result).to eq("Hello! How can I help you?")
      end

      it "configures the chat with correct parameters" do
        expect(RubyLLM).to receive(:chat).with(model: client.model)
        expect(mock_chat).to receive(:with_instructions).with(system_prompt)
        expect(mock_chat).to receive(:with_temperature).with(0.3)
        expect(mock_chat).to receive(:with_params).with(max_tokens: 1000)

        client.chat(system_prompt: system_prompt, user_prompt: user_prompt)
      end
    end

    context "with rate limit error" do
      let(:rate_limit_error) do
        error = RubyLLM::RateLimitError.allocate
        error.instance_variable_set(:@message, "Too many requests")
        allow(error).to receive(:message).and_return("Too many requests")
        error
      end

      before do
        allow(RubyLLM).to receive(:chat).and_raise(rate_limit_error)
      end

      it "wraps in LLM::RateLimitError" do
        expect { client.chat(system_prompt: system_prompt, user_prompt: user_prompt) }
          .to raise_error(LLM::RateLimitError, "Too many requests")
      end

      it "includes original error" do
        begin
          client.chat(system_prompt: system_prompt, user_prompt: user_prompt)
        rescue LLM::RateLimitError => e
          expect(e.original_error).to be_a(RubyLLM::RateLimitError)
        end
      end
    end

    context "with authentication error" do
      let(:auth_error) do
        error = RubyLLM::UnauthorizedError.allocate
        error.instance_variable_set(:@message, "Invalid API key")
        allow(error).to receive(:message).and_return("Invalid API key")
        error
      end

      before do
        allow(RubyLLM).to receive(:chat).and_raise(auth_error)
      end

      it "wraps in LLM::ConfigurationError" do
        expect { client.chat(system_prompt: system_prompt, user_prompt: user_prompt) }
          .to raise_error(LLM::ConfigurationError, /Authentication failed/)
      end
    end

    context "with server error" do
      let(:server_error) do
        error = RubyLLM::ServerError.allocate
        error.instance_variable_set(:@message, "Internal server error")
        allow(error).to receive(:message).and_return("Internal server error")
        error
      end

      before do
        allow(RubyLLM).to receive(:chat).and_raise(server_error)
      end

      it "wraps in LLM::APIError" do
        expect { client.chat(system_prompt: system_prompt, user_prompt: user_prompt) }
          .to raise_error(LLM::APIError, "Internal server error")
      end
    end

    context "with empty response" do
      let(:mock_response) { double("response", content: nil) }
      let(:mock_chat) { double("chat") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_params).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "raises InvalidResponseError" do
        expect { client.chat(system_prompt: system_prompt, user_prompt: user_prompt) }
          .to raise_error(LLM::InvalidResponseError, /Empty response/)
      end
    end

    context "with blank response" do
      let(:mock_response) { double("response", content: "   ") }
      let(:mock_chat) { double("chat") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_params).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "raises InvalidResponseError" do
        expect { client.chat(system_prompt: system_prompt, user_prompt: user_prompt) }
          .to raise_error(LLM::InvalidResponseError, /Empty response/)
      end
    end
  end

  describe "#provider_info" do
    let(:client) { described_class.new(max_tokens: 2000, temperature: 0.5) }

    it "returns provider configuration details" do
      info = client.provider_info
      expect(info[:provider]).to eq("anthropic")
      expect(info[:model]).to eq(Settings.llm.anthropic.model)
      expect(info[:max_tokens]).to eq(2000)
      expect(info[:temperature]).to eq(0.5)
    end
  end
end
