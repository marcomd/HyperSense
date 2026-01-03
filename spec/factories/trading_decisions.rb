# frozen_string_literal: true

FactoryBot.define do
  factory :trading_decision do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    association :macro_strategy, factory: :macro_strategy
    symbol { "BTC" }
    context_sent { { timestamp: Time.current.iso8601, symbol: "BTC" } }
    llm_response { { raw: "{}", parsed: {} } }
    parsed_decision do
      {
        "operation" => "open",
        "symbol" => "BTC",
        "direction" => "long",
        "leverage" => 5,
        "target_position" => 0.02,
        "stop_loss" => 95_000,
        "take_profit" => 105_000,
        "confidence" => 0.78,
        "reasoning" => "RSI neutral, MACD bullish crossover"
      }
    end
    operation { "open" }
    direction { "long" }
    confidence { 0.78 }
    executed { false }
    status { "pending" }
    llm_model { "claude-sonnet-4-5" }

    trait :hold do
      operation { "hold" }
      direction { nil }
      parsed_decision do
        {
          "operation" => "hold",
          "confidence" => 0.5,
          "reasoning" => "No clear setup"
        }
      end
    end

    trait :close do
      operation { "close" }
      direction { nil }
      parsed_decision do
        {
          "operation" => "close",
          "symbol" => "BTC",
          "confidence" => 0.85,
          "reasoning" => "Take profit target reached"
        }
      end
    end

    trait :short do
      direction { "short" }
      parsed_decision do
        {
          "operation" => "open",
          "symbol" => "BTC",
          "direction" => "short",
          "leverage" => 3,
          "target_position" => 0.015,
          "stop_loss" => 100_000,
          "take_profit" => 90_000,
          "confidence" => 0.72,
          "reasoning" => "Breaking below support"
        }
      end
    end

    trait :approved do
      status { "approved" }
    end

    trait :rejected do
      status { "rejected" }
      rejection_reason { "Low confidence" }
    end

    trait :executed do
      status { "executed" }
      executed { true }
    end

    trait :low_confidence do
      confidence { 0.45 }
    end

    trait :without_macro_strategy do
      macro_strategy { nil }
    end
  end
end
