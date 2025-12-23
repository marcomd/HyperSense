# frozen_string_literal: true

FactoryBot.define do
  factory :position do
    symbol { "BTC" }
    direction { "long" }
    size { 0.1 }
    entry_price { 100_000 }
    current_price { 100_000 }
    leverage { 5 }
    margin_used { 2_000 }
    unrealized_pnl { 0 }
    liquidation_price { 80_000 }
    status { "open" }
    hyperliquid_data { {} }
    opened_at { Time.current }
    closed_at { nil }

    trait :short do
      direction { "short" }
      liquidation_price { 120_000 }
    end

    trait :closed do
      status { "closed" }
      closed_at { Time.current }
    end

    trait :closing do
      status { "closing" }
    end

    trait :profitable do
      direction { "long" }
      entry_price { 100_000 }
      current_price { 110_000 }
      unrealized_pnl { 1_000 }
    end

    trait :losing do
      direction { "long" }
      entry_price { 100_000 }
      current_price { 95_000 }
      unrealized_pnl { -500 }
    end

    trait :eth do
      symbol { "ETH" }
      entry_price { 3_500 }
      current_price { 3_500 }
      liquidation_price { 2_800 }
    end

    trait :sol do
      symbol { "SOL" }
      entry_price { 200 }
      current_price { 200 }
      liquidation_price { 160 }
    end

    trait :high_leverage do
      leverage { 20 }
      margin_used { 500 }
      liquidation_price { 95_000 }
    end

    trait :with_hyperliquid_data do
      hyperliquid_data do
        {
          "coin" => "BTC",
          "entryPx" => "100000.0",
          "positionValue" => "10000.0",
          "unrealizedPnl" => "0.0",
          "returnOnEquity" => "0.0",
          "liquidationPx" => "80000.0",
          "marginUsed" => "2000.0",
          "maxTradeSzs" => [ "1.0", "1.0" ]
        }
      end
    end
  end
end
