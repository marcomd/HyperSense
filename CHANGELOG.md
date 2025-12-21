# Changelog

All notable changes to HyperSense.

## [0.2.0] - 2024-12-21

### Added
- **Data Pipeline** (Phase 2 complete)
  - `DataIngestion::PriceFetcher` - Binance API integration for BTC, ETH, SOL, BNB
  - `DataIngestion::SentimentFetcher` - Fear & Greed Index with interpretation
  - `Indicators::Calculator` - EMA, RSI, MACD, Pivot Points
  - `MarketSnapshot` model with JSONB indicators storage
  - `MarketSnapshotJob` - Captures market data every minute
- Hyperliquid gem integration (forked: github.com/marcomd/hyperliquid)

## [0.1.0] - 2024-12-21

### Added
- **Foundation** (Phase 1 complete)
  - Rails 8.1 API-only application
  - PostgreSQL 16 via Docker (port 5433)
  - Solid Queue for background jobs (no Redis)
  - Service architecture (`data_ingestion/`, `indicators/`, `reasoning/`, `execution/`, `risk/`)
  - Job stubs: `TradingCycleJob`, `MacroStrategyJob`, `MarketSnapshotJob`
  - Configuration via `config/settings.yml`
  - RSpec + VCR testing setup
  - CORS configured for React frontend
