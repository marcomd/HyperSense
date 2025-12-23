# frozen_string_literal: true

FactoryBot.define do
  factory :execution_log do
    loggable { nil }
    action { "place_order" }
    status { "success" }
    request_payload { { symbol: "BTC", action: "place_order" } }
    response_payload { { status: "ok" } }
    error_message { nil }
    executed_at { Time.current }

    trait :failure do
      status { "failure" }
      error_message { "Connection timeout" }
      response_payload { { status: "error", message: "Connection timeout" } }
    end

    trait :place_order do
      action { "place_order" }
      request_payload do
        {
          symbol: "BTC",
          order_type: "market",
          side: "buy",
          size: 0.1
        }
      end
    end

    trait :cancel_order do
      action { "cancel_order" }
      request_payload do
        {
          order_id: "HL-abc123",
          symbol: "BTC"
        }
      end
    end

    trait :modify_order do
      action { "modify_order" }
      request_payload do
        {
          order_id: "HL-abc123",
          new_price: 100_500,
          new_size: 0.15
        }
      end
    end

    trait :sync_position do
      action { "sync_position" }
      request_payload { { symbol: "BTC" } }
      response_payload do
        {
          positions: [
            {
              symbol: "BTC",
              size: 0.1,
              entry_price: 100_000
            }
          ]
        }
      end
    end

    trait :sync_account do
      action { "sync_account" }
      request_payload { { address: "0x123..." } }
      response_payload do
        {
          balance: 10_000,
          margin_used: 2_000,
          available_margin: 8_000
        }
      end
    end

    trait :for_position do
      association :loggable, factory: :position
    end

    trait :for_order do
      association :loggable, factory: :order
    end

    trait :with_duration do
      response_payload { { status: "ok", duration_ms: 150 } }
    end
  end
end
