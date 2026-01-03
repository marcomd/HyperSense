# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    trading_decision { nil }
    position { nil }
    symbol { "BTC" }
    order_type { "market" }
    side { "buy" }
    size { 0.1 }
    price { nil }
    stop_price { nil }
    status { "pending" }
    hyperliquid_order_id { nil }
    hyperliquid_response { {} }
    filled_size { nil }
    average_fill_price { nil }
    submitted_at { nil }
    filled_at { nil }

    trait :limit_order do
      order_type { "limit" }
      price { 99_500 }
    end

    trait :stop_limit_order do
      order_type { "stop_limit" }
      price { 99_500 }
      stop_price { 99_000 }
    end

    trait :sell do
      side { "sell" }
    end

    trait :submitted do
      status { "submitted" }
      hyperliquid_order_id { "HL-#{SecureRandom.hex(8)}" }
      submitted_at { Time.current }
    end

    trait :filled do
      status { "filled" }
      hyperliquid_order_id { "HL-#{SecureRandom.hex(8)}" }
      submitted_at { 5.minutes.ago }
      filled_at { Time.current }
      filled_size { 0.1 }
      average_fill_price { 100_050 }
    end

    trait :partially_filled do
      status { "partially_filled" }
      hyperliquid_order_id { "HL-#{SecureRandom.hex(8)}" }
      submitted_at { 5.minutes.ago }
      filled_size { 0.05 }
      average_fill_price { 100_025 }
    end

    trait :cancelled do
      status { "cancelled" }
      hyperliquid_order_id { "HL-#{SecureRandom.hex(8)}" }
      submitted_at { 10.minutes.ago }
      hyperliquid_response { { "cancel_reason" => "User requested" } }
    end

    trait :failed do
      status { "failed" }
      hyperliquid_response { { "error" => "Insufficient margin" } }
    end

    trait :with_trading_decision do
      association :trading_decision, factory: :trading_decision
    end

    trait :with_position do
      association :position, factory: :position
    end

    trait :eth do
      symbol { "ETH" }
    end

    trait :sol do
      symbol { "SOL" }
    end

    trait :with_hyperliquid_response do
      hyperliquid_response do
        {
          "status" => "ok",
          "response" => {
            "type" => "order",
            "data" => {
              "statuses" => [ { "resting" => { "oid" => 12_345 } } ]
            }
          }
        }
      end
    end
  end
end
