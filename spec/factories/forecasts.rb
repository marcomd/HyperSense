# frozen_string_literal: true

FactoryBot.define do
  factory :forecast do
    symbol { "BTC" }
    timeframe { "1h" }
    current_price { 98_000.0 }
    predicted_price { 99_000.0 }
    forecast_for { 1.hour.from_now }

    trait :bearish do
      predicted_price { 96_000.0 }
    end

    trait :neutral do
      predicted_price { current_price }
    end

    trait :validated do
      actual_price { 98_800.0 }
      mae { (predicted_price - actual_price).abs }
      mape { ((predicted_price - actual_price).abs / actual_price * 100) }
    end

    trait :eth do
      symbol { "ETH" }
      current_price { 3_400.0 }
      predicted_price { 3_500.0 }
    end

    trait :short_term do
      timeframe { "15m" }
      forecast_for { 15.minutes.from_now }
    end
  end
end
