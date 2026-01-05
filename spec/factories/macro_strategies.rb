# frozen_string_literal: true

FactoryBot.define do
  factory :macro_strategy do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    market_narrative { "Bitcoin showing strength above 50-day EMA with bullish momentum." }
    bias { "bullish" }
    risk_tolerance { 0.7 }
    key_levels do
      {
        "BTC" => { "support" => [ 95_000, 92_000 ], "resistance" => [ 100_000, 105_000 ] },
        "ETH" => { "support" => [ 3200, 3000 ], "resistance" => [ 3500, 3800 ] },
        "SOL" => { "support" => [ 180, 170 ], "resistance" => [ 200, 220 ] },
        "BNB" => { "support" => [ 650, 620 ], "resistance" => [ 700, 750 ] }
      }
    end
    context_used { { timestamp: Time.current.iso8601, assets: %w[BTC ETH SOL BNB] } }
    llm_response { { raw: "{}", parsed: {} } }
    valid_until { 24.hours.from_now }
    llm_model { "claude-sonnet-4-5" }

    trait :bearish do
      market_narrative { "Market showing weakness, breaking below key support levels." }
      bias { "bearish" }
      risk_tolerance { 0.3 }
    end

    trait :neutral do
      market_narrative { "Market consolidating in range, no clear direction." }
      bias { "neutral" }
      risk_tolerance { 0.5 }
    end

    trait :stale do
      valid_until { 1.hour.ago }
    end

    trait :active do
      valid_until { 24.hours.from_now }
    end

    trait :fallback do
      market_narrative { "Unable to parse LLM response. Defaulting to neutral stance." }
      bias { "neutral" }
      risk_tolerance { 0.5 }
      key_levels { {} }
      valid_until { 6.hours.from_now }
    end

    trait :conservative do
      risk_tolerance { 0.2 }
    end

    trait :aggressive do
      risk_tolerance { 0.9 }
    end
  end
end
