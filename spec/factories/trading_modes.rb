# frozen_string_literal: true

FactoryBot.define do
  factory :trading_mode do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    mode { "enabled" }
    changed_by { "system" }
    reason { nil }

    trait :exit_only do
      mode { "exit_only" }
    end

    trait :blocked do
      mode { "blocked" }
    end

    trait :circuit_breaker_triggered do
      mode { "exit_only" }
      changed_by { "circuit_breaker" }
      reason { "Daily loss exceeded 5%" }
    end
  end
end
