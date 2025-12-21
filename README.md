# HyperSense

**Version 0.2.0** | Autonomous AI Trading Agent for cryptocurrency markets.

## Overview

HyperSense is an autonomous trading agent that operates in discrete cycles to analyze market data and execute trades on decentralized exchanges (DEX). It uses Claude AI for reasoning and decision-making.

### Key Features

- **Autonomous Operation**: Runs every 3-15 minutes without human intervention
- **Multi-Agent Architecture**: High-level (macro strategy) + Low-level (trade execution) agents
- **Technical Analysis**: EMA, RSI, MACD, Pivot Points
- **Risk Management**: Position sizing, stop-loss, take-profit, confidence scoring
- **Real-time Dashboard**: React frontend for monitoring (coming soon)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR                             │
│              (TradingCycleJob - every 5 min)               │
│                   Via Solid Queue                           │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
┌─────────────────────┐                ┌─────────────────────┐
│   HIGH-LEVEL AGENT  │                │   LOW-LEVEL AGENT   │
│   (Macro Strategist)│                │   (Trade Executor)  │
├─────────────────────┤                ├─────────────────────┤
│ Frequency: Daily    │                │ Frequency: 5 min    │
│                     │                │                     │
│ Inputs:             │                │ Inputs:             │
│ - Weekly trends     │                │ - Current prices    │
│ - Macro sentiment   │                │ - Live indicators   │
│ - News/events       │                │ - Macro strategy    │
│                     │                │                     │
│ Outputs:            │                │ Outputs:            │
│ - Market narrative  │                │ - Specific trades   │
│ - Bias direction    │                │ - Entry/exit points │
│ - Risk tolerance    │                │ - Position sizing   │
└─────────────────────┘                └─────────────────────┘
                              │
                              ▼
              ┌──────────────────────────┐
              │   DATA INGESTION LAYER   │
              │ PriceFetcher (Binance)   │
              │ SentimentFetcher (F&G)   │
              │ Indicators::Calculator   │
              └──────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────┐
              │   MarketSnapshot (PG)    │
              │   Solid Queue (no Redis) │
              └──────────────────────────┘
```

## Tech Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Framework | Rails 8.1 API | Latest version |
| Database | PostgreSQL 16 | Port 5433 (avoids local PG conflict) |
| Job Queue | Solid Queue | No Redis needed! |
| Scheduling | recurring.yml | Built into Solid Queue |
| LLM | Anthropic Ruby SDK | Official SDK |
| Exchange | hyperliquid gem (forked) | Extend with write ops |
| Signing | eth gem | EIP-712 for Hyperliquid |
| Frontend | React + Vite + TypeScript | Rich charting |
| Deployment | Docker Compose | Simple VPS setup |

## Project Structure

```
HyperSense/
├── backend/                         # Rails 8 API
│   ├── app/
│   │   ├── jobs/                   # Solid Queue jobs
│   │   │   ├── trading_cycle_job.rb
│   │   │   ├── macro_strategy_job.rb
│   │   │   └── market_snapshot_job.rb
│   │   ├── models/
│   │   │   └── market_snapshot.rb  # Time-series market data
│   │   └── services/
│   │       ├── data_ingestion/
│   │       │   ├── price_fetcher.rb      # Binance API
│   │       │   └── sentiment_fetcher.rb  # Fear & Greed Index
│   │       ├── indicators/
│   │       │   └── calculator.rb         # EMA, RSI, MACD, Pivots
│   │       ├── reasoning/           # TODO: Phase 3
│   │       ├── execution/           # TODO: Phase 4
│   │       └── risk/                # TODO: Phase 5
│   │       └── trading_cycle.rb     # Main orchestrator (stub)
│   ├── config/
│   │   ├── settings.yml            # Trading parameters
│   │   ├── recurring.yml           # Job schedules
│   │   ├── queue.yml               # Queue workers
│   │   └── database.yml            # PostgreSQL (port 5433)
│   └── spec/
│       └── services/
│           ├── indicators/calculator_spec.rb
│           └── data_ingestion/
├── frontend/                        # React dashboard (TODO: Phase 6)
├── docker-compose.yml               # PostgreSQL only
└── .tool-versions                   # Ruby 3.4.4, Node 24.11.1
```

## Requirements

- Ruby 3.4.4 (via asdf)
- Node.js 24.11.1 (via asdf)
- PostgreSQL 16 (via Docker)
- Docker & Docker Compose

## Setup

1. **Install Ruby and Node via asdf**
   ```bash
   asdf install
   ```

2. **Install dependencies**
   ```bash
   cd backend
   bundle install
   ```

3. **Start PostgreSQL** (uses port 5433 to avoid conflicts)
   ```bash
   docker compose up -d
   ```

4. **Setup database**
   ```bash
   cd backend
   rails db:create db:migrate
   ```

5. **Configure API keys**
   ```bash
   EDITOR="code --wait" rails credentials:edit
   ```
   Add:
   ```yaml
   anthropic:
     api_key: your_anthropic_api_key
   hyperliquid:
     private_key: your_wallet_private_key
     address: your_wallet_address
   ```

6. **Test data pipeline**
   ```bash
   rails runner "MarketSnapshotJob.perform_now"
   ```

7. **Run the server**
   ```bash
   bin/dev
   ```

8. **Start background jobs**
   ```bash
   bin/jobs
   ```

## Configuration

Edit `config/settings.yml` to customize:

```yaml
# Trading Assets
assets:
  - BTC
  - ETH
  - SOL
  - BNB

# Trading Cycle Configuration
trading:
  cycle_interval_minutes: 5
  paper_trading: true            # Safe mode - no real trades

# Risk Management
risk:
  max_position_size: 0.05        # Max 5% of capital per trade
  min_confidence: 0.6            # Minimum confidence score
  max_leverage: 10
  default_leverage: 3

# Context Weights for Reasoning
weights:
  forecast: 0.6
  sentiment: 0.2
  technical: 0.15
  whale_alerts: 0.05
```

## Current Implementation

### Data Pipeline (Working)

```ruby
# Fetch and store market data with indicators
MarketSnapshotJob.perform_now

# Example output:
# BTC: $97000.0 | RSI: 60.1 | MACD: 46.03
# ETH: $3200.0  | RSI: 66.0 | MACD: 1.98
# SOL: $190.0   | RSI: 45.0 | MACD: -0.0
# BNB: $700.0   | RSI: 60.1 | MACD: 0.68
```

### Technical Indicators

```ruby
calculator = Indicators::Calculator.new

# EMA (Exponential Moving Average)
calculator.ema(prices, 20)   # EMA-20
calculator.ema(prices, 50)   # EMA-50
calculator.ema(prices, 100)  # EMA-100

# RSI (Relative Strength Index)
calculator.rsi(prices, 14)   # 0-100, oversold < 30, overbought > 70

# MACD
calculator.macd(prices)      # { macd:, signal:, histogram: }

# Pivot Points
calculator.pivot_points(high, low, close)  # { pp:, r1:, r2:, s1:, s2: }
```

### MarketSnapshot Model

```ruby
# Get latest snapshot for BTC
snapshot = MarketSnapshot.latest_for("BTC")
snapshot.price           # => 97000.0
snapshot.rsi_signal      # => :neutral / :oversold / :overbought
snapshot.macd_signal     # => :bullish / :bearish
snapshot.above_ema?(50)  # => true/false

# Query historical data
MarketSnapshot.for_symbol("ETH").last_hours(24)
MarketSnapshot.prices_for("BTC", limit: 150)  # For indicator calculation
```

---

## Development Status

### Phase 1: Foundation ✅
- [x] Rails 8 API setup
- [x] PostgreSQL + Docker (port 5433)
- [x] Solid Queue configuration
- [x] Service architecture
- [x] RSpec + VCR setup

### Phase 2: Data Pipeline ✅
- [x] Price fetcher (Binance API)
- [x] Sentiment fetcher (Fear & Greed Index)
- [x] Technical indicators (EMA, RSI, MACD, Pivot Points)
- [x] MarketSnapshot model with JSONB indicators
- [x] MarketSnapshotJob (runs every minute)

### Phase 3: Reasoning Engine 🚧
- [ ] MacroStrategy model
- [ ] TradingDecision model
- [ ] Context assembler
- [ ] High-level agent (macro strategy)
- [ ] Low-level agent (trade execution)
- [ ] Decision parser with JSON validation

### Phase 4: Hyperliquid Integration
- [ ] Read operations (via forked gem)
- [ ] Write operations (orders, leverage)
- [ ] EIP-712 signing
- [ ] Position model

### Phase 5: Risk Management
- [ ] Position sizing
- [ ] Stop-loss / Take-profit
- [ ] Circuit breakers
- [ ] Paper trading mode

### Phase 6: Dashboard
- [ ] React frontend (Vite + TypeScript)
- [ ] Equity curve (recharts/lightweight-charts)
- [ ] Position tracking
- [ ] Decision logs
- [ ] ActionCable WebSocket

### Phase 7: Production
- [ ] Dockerfile
- [ ] docker-compose.production.yml
- [ ] Monitoring/alerting

---

## Implementation Plan (Phases 3-7)

### Phase 3: Multi-Agent Reasoning Engine

**Files to create:**
- `app/models/macro_strategy.rb`
- `app/models/trading_decision.rb`
- `app/services/reasoning/context_assembler.rb`
- `app/services/reasoning/high_level_agent.rb`
- `app/services/reasoning/low_level_agent.rb`
- `app/services/reasoning/decision_parser.rb`

**MacroStrategy Schema:**
```ruby
create_table :macro_strategies do |t|
  t.string :market_narrative
  t.string :bias  # bullish/bearish/neutral
  t.decimal :risk_tolerance  # 0.0 - 1.0
  t.jsonb :key_levels  # support/resistance
  t.jsonb :context_used
  t.datetime :valid_until
  t.timestamps
end
```

**TradingDecision Schema:**
```ruby
create_table :trading_decisions do |t|
  t.jsonb :context_sent      # Full prompt context
  t.jsonb :llm_response      # Raw LLM output
  t.jsonb :parsed_decision   # Structured decision
  t.boolean :executed
  t.string :rejection_reason
  t.timestamps
end
```

**LLM Output Schema:**
```json
{
  "operation": "open",
  "symbol": "BTC",
  "direction": "long",
  "leverage": 5,
  "target_position": 0.02,
  "stop_loss": 95000,
  "take_profit": 105000,
  "confidence": 0.78,
  "reasoning": "..."
}
```

**High-Level Agent (Macro):**
- Runs daily at 6am
- Analyzes weekly trends, macro sentiment, news
- Outputs: market narrative, bias (bullish/bearish/neutral), risk tolerance

**Low-Level Agent (Execution):**
- Runs every 5 minutes
- Inputs: current prices, live indicators, macro strategy
- Outputs: specific trades, entry/exit points, position sizing

### Phase 4: Hyperliquid Gem Extension

**Forked gem:** https://github.com/marcomd/hyperliquid

**Current capabilities (read-only):**
```ruby
client = Hyperliquid::Client.new
client.all_mids              # Get all mid prices
client.user_state(address)   # Account state
client.open_orders(address)  # Open orders
```

**Extensions to add:**
```ruby
client.place_order(order_params)   # Place limit/market order
client.cancel_order(order_id)      # Cancel order
client.modify_order(order_id, params)
client.set_leverage(symbol, leverage)
```

**Files to create (in forked gem):**
- `lib/hyperliquid/signer.rb` - EIP-712 signing using `eth` gem
- `lib/hyperliquid/exchange.rb` - Write operations
- `spec/hyperliquid/exchange_spec.rb`

**Files to create (in backend):**
- `app/models/position.rb`
- `app/services/execution/trade_executor.rb`

**Position Schema:**
```ruby
create_table :positions do |t|
  t.string :symbol, null: false
  t.string :direction  # long/short
  t.decimal :entry_price
  t.decimal :size
  t.integer :leverage
  t.decimal :stop_loss
  t.decimal :take_profit
  t.string :status  # open/closed/liquidated
  t.timestamps
end
```

### Phase 5: Risk Management & Orchestration

**Files to create:**
- `app/services/risk/risk_manager.rb`
- Update `app/services/trading_cycle.rb`

**RiskManager:**
```ruby
class Risk::RiskManager
  MAX_POSITION_SIZE = 0.05  # 5% of capital
  MIN_CONFIDENCE = 0.6

  def validate(decision, portfolio)
    return reject("Low confidence") if decision.confidence < MIN_CONFIDENCE
    return reject("Position too large") if exceeds_limits?(decision, portfolio)
    approve(decision)
  end
end
```

**TradingCycle Orchestration:**
```ruby
class TradingCycle
  def execute
    # 1. Check if macro strategy needs refresh (daily)
    refresh_macro_strategy if macro_strategy_stale?

    # 2. Run low-level agent with macro context
    decision = low_level_agent.decide(
      market_data: fetch_market_data,
      macro_strategy: current_macro_strategy
    )

    # 3. Execute if approved by risk manager
    execute_decision(decision) if risk_manager.validate(decision).approved?
  end
end
```

### Phase 6: React Dashboard

**Structure:**
```
frontend/
├── src/
│   ├── components/
│   │   ├── EquityCurve.tsx
│   │   ├── PositionsTable.tsx
│   │   ├── DecisionLog.tsx
│   │   ├── MacroStrategy.tsx
│   │   └── PriceChart.tsx
│   ├── hooks/
│   │   └── useWebSocket.ts
│   └── pages/
│       └── Dashboard.tsx
└── package.json
```

**Charting:** `recharts` or `lightweight-charts` (TradingView)

**Real-time:** ActionCable WebSocket → React subscription

**API Controllers to create:**
```ruby
# app/controllers/api/v1/
├── positions_controller.rb
├── decisions_controller.rb
├── market_data_controller.rb
└── dashboard_controller.rb
```

### Phase 7: Production Deployment

**docker-compose.production.yml:**
```yaml
services:
  app:
    build: ./backend
    environment:
      - RAILS_ENV=production
      - DATABASE_URL=postgres://db:5432/hypersense
    ports:
      - "3001:3000"

  solid_queue:
    build: ./backend
    command: bundle exec rails solid_queue:start

  frontend:
    build: ./frontend
    ports:
      - "3000:80"

  db:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

**Recommended VPS:** 2GB RAM minimum (DigitalOcean, Hetzner, Linode)

---

## Confirmed Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | Ruby (Rails 8) | User expertise 10/10, excellent for scheduled jobs |
| Job Queue | Solid Queue | No Redis needed, PostgreSQL-backed |
| Target DEX | Hyperliquid | Best for perps, good API |
| Dashboard | Rails API + React | Rich charting, TypeScript |
| Agent Structure | Multi-agent | High-level (macro) + Low-level (execution) |
| Deployment | Local / VPS | Docker Compose |

---

## Testing

```bash
cd backend

# Run all specs
rspec

# Run specific specs
rspec spec/services/indicators/calculator_spec.rb

# Test data pipeline manually
rails runner "MarketSnapshotJob.perform_now"
rails runner "puts MarketSnapshot.count"
```

---

## Related Repositories

- [Hyperliquid Ruby Gem](https://github.com/marcomd/hyperliquid) - Forked for write operations

## License

Private - All rights reserved
