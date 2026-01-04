# frozen_string_literal: true

FactoryBot.define do
  factory :risk_profile do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    name { "moderate" }
    changed_by { "system" }

    trait :cautious do
      name { "cautious" }
    end

    trait :fearless do
      name { "fearless" }
    end
  end
end
