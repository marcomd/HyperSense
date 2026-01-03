# frozen_string_literal: true

FactoryBot.define do
  factory :market_snapshot do
    before(:create) { raise "FactoryBot should only be used in test environment!" unless Rails.env.test? }

    symbol { "BTC" }
    price { 97_000 }
    high_24h { 98_500 }
    low_24h { 95_000 }
    volume_24h { 50_000_000 }
    price_change_pct_24h { 2.5 }
    indicators do
      {
        "ema_20" => 96_500,
        "ema_50" => 95_000,
        "ema_100" => 92_000,
        "ema_200" => 90_000,
        "rsi_14" => 62.5,
        "atr_14" => 1_455.0,
        "macd" => { "macd" => 250.0, "signal" => 200.0, "histogram" => 50.0 },
        "pivot_points" => { "pp" => 96_833, "r1" => 98_166, "r2" => 99_333, "s1" => 95_666, "s2" => 94_333 }
      }
    end
    sentiment do
      {
        "fear_greed" => { "value" => 65, "classification" => "Greed" },
        "fetched_at" => Time.current.iso8601
      }
    end
    captured_at { Time.current }

    trait :eth do
      symbol { "ETH" }
      price { 3_400 }
      high_24h { 3_500 }
      low_24h { 3_300 }
      volume_24h { 25_000_000 }
      indicators do
        {
          "ema_20" => 3_350,
          "ema_50" => 3_200,
          "ema_100" => 3_000,
          "ema_200" => 2_800,
          "rsi_14" => 58.0,
          "atr_14" => 51.0,
          "macd" => { "macd" => 25.0, "signal" => 20.0, "histogram" => 5.0 },
          "pivot_points" => { "pp" => 3_400, "r1" => 3_500, "r2" => 3_600, "s1" => 3_300, "s2" => 3_200 }
        }
      end
    end

    trait :sol do
      symbol { "SOL" }
      price { 190 }
      high_24h { 195 }
      low_24h { 185 }
    end

    trait :bnb do
      symbol { "BNB" }
      price { 700 }
      high_24h { 710 }
      low_24h { 690 }
    end

    trait :oversold do
      indicators do
        {
          "ema_20" => 98_000,
          "ema_50" => 99_000,
          "rsi_14" => 25.0,
          "atr_14" => 1_940.0,
          "macd" => { "macd" => -100.0, "signal" => -50.0, "histogram" => -50.0 }
        }
      end
    end

    trait :overbought do
      indicators do
        {
          "ema_20" => 95_000,
          "ema_50" => 93_000,
          "rsi_14" => 78.0,
          "atr_14" => 970.0,
          "macd" => { "macd" => 300.0, "signal" => 250.0, "histogram" => 50.0 }
        }
      end
    end

    # ATR volatility traits for testing atr_signal
    # Low volatility: ATR < 1% of price
    trait :low_volatility do
      price { 100_000 }
      indicators do
        {
          "ema_20" => 99_000,
          "ema_50" => 98_000,
          "rsi_14" => 50.0,
          "atr_14" => 500.0,
          "macd" => { "macd" => 100.0, "signal" => 80.0, "histogram" => 20.0 }
        }
      end
    end

    # Normal volatility: 1% <= ATR < 2% of price
    trait :normal_volatility do
      price { 100_000 }
      indicators do
        {
          "ema_20" => 99_000,
          "ema_50" => 98_000,
          "rsi_14" => 50.0,
          "atr_14" => 1_500.0,
          "macd" => { "macd" => 100.0, "signal" => 80.0, "histogram" => 20.0 }
        }
      end
    end

    # High volatility: 2% <= ATR < 3% of price
    trait :high_volatility do
      price { 100_000 }
      indicators do
        {
          "ema_20" => 99_000,
          "ema_50" => 98_000,
          "rsi_14" => 50.0,
          "atr_14" => 2_500.0,
          "macd" => { "macd" => 100.0, "signal" => 80.0, "histogram" => 20.0 }
        }
      end
    end

    # Very high volatility: ATR >= 3% of price
    trait :very_high_volatility do
      price { 100_000 }
      indicators do
        {
          "ema_20" => 99_000,
          "ema_50" => 98_000,
          "rsi_14" => 50.0,
          "atr_14" => 3_500.0,
          "macd" => { "macd" => 100.0, "signal" => 80.0, "histogram" => 20.0 }
        }
      end
    end

    trait :extreme_fear do
      sentiment do
        {
          "fear_greed" => { "value" => 15, "classification" => "Extreme Fear" },
          "fetched_at" => Time.current.iso8601
        }
      end
    end

    trait :extreme_greed do
      sentiment do
        {
          "fear_greed" => { "value" => 85, "classification" => "Extreme Greed" },
          "fetched_at" => Time.current.iso8601
        }
      end
    end
  end
end
