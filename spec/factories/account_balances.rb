# frozen_string_literal: true

FactoryBot.define do
  factory :account_balance do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    balance { 10_000.0 }
    event_type { "sync" }
    source { "hyperliquid" }
    hyperliquid_data { {} }
    recorded_at { Time.current }

    trait :initial do
      event_type { "initial" }
      previous_balance { nil }
      delta { nil }
    end

    trait :sync do
      event_type { "sync" }
      previous_balance { 10_000.0 }
      delta { 100.0 }
      balance { 10_100.0 }
    end

    trait :deposit do
      event_type { "deposit" }
      previous_balance { 10_000.0 }
      delta { 5_000.0 }
      balance { 15_000.0 }
      notes { "External deposit detected" }
    end

    trait :withdrawal do
      event_type { "withdrawal" }
      previous_balance { 10_000.0 }
      delta { -2_000.0 }
      balance { 8_000.0 }
      notes { "External withdrawal detected" }
    end

    trait :adjustment do
      event_type { "adjustment" }
      previous_balance { 10_000.0 }
      delta { 50.0 }
      balance { 10_050.0 }
      notes { "Manual reconciliation adjustment" }
    end

    trait :with_hyperliquid_data do
      hyperliquid_data do
        {
          "crossMarginSummary" => {
            "accountValue" => "10000.0",
            "totalMarginUsed" => "2000.0",
            "totalRawUsd" => "8000.0"
          }
        }
      end
    end
  end
end
