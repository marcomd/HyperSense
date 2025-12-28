# HyperSense

**Version 0.13.4** | Autonomous AI Trading Agent for cryptocurrency markets.

![HyperSense_cover1.jpg](docs/HyperSense_cover1.jpg)

## Overview

HyperSense is an autonomous trading agent that operates in discrete cycles to analyze market data and execute trades on decentralized exchanges (DEX). It uses Claude AI for reasoning and decision-making.

### Key Features

- **Autonomous Operation**: Runs every 3-15 minutes without human intervention
- **Multi-Agent Architecture**: High-level (macro strategy) + Low-level (trade execution) agents
- **Technical Analysis**: EMA, RSI, MACD, Pivot Points
- **Risk Management**: Position sizing, stop-loss, take-profit, confidence scoring
- **Real-time Dashboard**: React frontend with routing, filters, and detail pages

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR                             │
│              (TradingCycleJob - every 5 min)                │
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
│ (6am or on-demand)  │                │                     │
│                     │                │ Inputs:             │
│ Inputs:             │                │ - Current prices    │
│ - Weekly trends     │                │ - Live indicators   │
│ - Macro sentiment   │                │ - Macro strategy    │
│ - News/events       │                │                     │
│                     │                │ Outputs:            │
│ Outputs:            │                │ - Specific trades   │
│ - Market narrative  │                │ - Entry/exit points │
│ - Bias direction    │                │ - Position sizing   │
│ - Risk tolerance    │                │                     │
└─────────────────────┘                └─────────────────────┘
                              │
                              ▼
              ┌──────────────────────────┐
              │   RISK MANAGEMENT LAYER  │
              │ RiskManager (validation) │
              │ RiskMonitoringJob (1min) │
              │ CircuitBreaker (halts)   │
              └──────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────┐
              │   DATA INGESTION LAYER   │
              │ MarketSnapshotJob (1min) │
              │ Indicators::Calculator   │
              └──────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────┐
              │   MarketSnapshot (PG)    │
              │   Solid Queue (no Redis) │
              └──────────────────────────┘
```

## Execution Flow

### Job Schedule

| Frequency | Job | Queue | Purpose |
|-----------|-----|-------|---------|
| Every minute | MarketSnapshotJob | data | Fetch prices, calculate indicators |
| Every minute | RiskMonitoringJob | risk | Monitor SL/TP, circuit breaker |
| Every 5 minutes | TradingCycleJob | trading | Main trading orchestration |
| Every 5 minutes | ForecastJob | analysis | Prophet price predictions (1m, 15m, 1h) |
| Daily (6am) | MacroStrategyJob | analysis | High-level market analysis |

### Trading Cycle (every 5 min)

1. **Circuit breaker check** - halt if triggered
2. **Position sync** - fetch positions from Hyperliquid
3. **Macro strategy** - ensure valid (refresh if stale)
4. **Low-level agent** - generate decisions for all assets
5. **Risk validation** - filter through RiskManager
6. **Trade execution** - execute approved trades

### 24-Hour Timeline

```
6:00 AM  → MacroStrategyJob creates daily strategy (bullish/bearish/neutral)
6:05 AM  → TradingCycleJob starts using macro strategy
All day  → MarketSnapshotJob (1min) + RiskMonitoringJob (1min)
All day  → TradingCycleJob (5min) makes decisions within macro bias
~6:00 PM → Macro strategy becomes stale → TradingCycleJob triggers refresh
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
| Frontend | React + Vite + TypeScript | Rich charting, React Router |
| Deployment | Docker Compose | Simple VPS setup |

## Project Structure

```
HyperSense/
├── backend/                         # Rails 8 API
│   ├── app/
│   │   ├── channels/               # ActionCable WebSocket channels
│   │   │   ├── dashboard_channel.rb     # Real-time dashboard updates
│   │   │   └── markets_channel.rb       # Price updates by symbol
│   │   ├── controllers/
│   │   │   └── api/v1/            # REST API endpoints
│   │   │       ├── dashboard_controller.rb
│   │   │       ├── positions_controller.rb
│   │   │       ├── decisions_controller.rb
│   │   │       ├── market_data_controller.rb
│   │   │       └── macro_strategies_controller.rb
│   │   ├── jobs/                   # Solid Queue jobs
│   │   │   ├── trading_cycle_job.rb
│   │   │   ├── macro_strategy_job.rb
│   │   │   ├── market_snapshot_job.rb
│   │   │   ├── risk_monitoring_job.rb
│   │   │   └── forecast_job.rb          # Prophet ML predictions
│   │   ├── models/
│   │   │   ├── market_snapshot.rb   # Time-series market data
│   │   │   ├── macro_strategy.rb    # Daily macro analysis
│   │   │   ├── trading_decision.rb  # Per-asset trade decisions
│   │   │   ├── position.rb          # Open/closed positions
│   │   │   ├── order.rb             # Exchange orders
│   │   │   ├── execution_log.rb     # Audit trail
│   │   │   └── forecast.rb          # Price predictions with MAE/MAPE
│   │   └── services/
│   │       ├── data_ingestion/
│   │       │   ├── price_fetcher.rb      # Binance API
│   │       │   ├── sentiment_fetcher.rb  # Fear & Greed Index
│   │       │   ├── news_fetcher.rb       # RSS news (coinjournal.net)
│   │       │   └── whale_alert_fetcher.rb # Large transfers (whale-alert.io)
│   │       ├── forecasting/
│   │       │   └── price_predictor.rb    # Prophet ML forecasting
│   │       ├── indicators/
│   │       │   └── calculator.rb         # EMA, RSI, MACD, Pivots
│   │       ├── reasoning/
│   │       │   ├── context_assembler.rb  # Weighted context for LLM
│   │       │   ├── decision_parser.rb    # JSON validation (dry-validation)
│   │       │   ├── high_level_agent.rb   # Macro strategy (daily)
│   │       │   └── low_level_agent.rb    # Trade decisions (5 min)
│   │       ├── execution/
│   │       │   ├── hyperliquid_client.rb # Exchange API wrapper
│   │       │   ├── account_manager.rb    # Account state
│   │       │   ├── position_manager.rb   # Position tracking
│   │       │   └── order_executor.rb     # Order execution
│   │       ├── risk/
│   │       │   ├── risk_manager.rb       # Centralized risk validation
│   │       │   ├── position_sizer.rb     # Risk-based position sizing
│   │       │   ├── stop_loss_manager.rb  # SL/TP enforcement
│   │       │   └── circuit_breaker.rb    # Trading halt on losses
│   │       └── trading_cycle.rb     # Main orchestrator
│   ├── config/
│   │   ├── settings.yml            # Trading parameters
│   │   ├── recurring.yml           # Job schedules
│   │   ├── queue.yml               # Queue workers
│   │   └── database.yml            # PostgreSQL (port 5433)
│   └── spec/
│       └── services/
│           ├── indicators/calculator_spec.rb
│           └── data_ingestion/
├── frontend/                        # React dashboard (Vite + TypeScript)
│   ├── src/
│   │   ├── api/                   # API client
│   │   ├── components/            # React components
│   │   │   ├── cards/            # AccountSummary, PositionsTable, DecisionLog, etc.
│   │   │   ├── charts/           # EquityCurve, PriceChart
│   │   │   ├── common/           # DataTable, PageLayout
│   │   │   ├── filters/          # DateRangeFilter, SymbolFilter, Pagination, etc.
│   │   │   └── layout/           # Header
│   │   ├── hooks/                # useApi, useWebSocket, useFilters, usePagination
│   │   ├── pages/                # Dashboard, ForecastsPage, MarketSnapshotsPage, etc.
│   │   └── types/                # TypeScript definitions
│   └── package.json
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

3. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env to customize database settings, LLM_MODEL and add Hyperliquid credentials
   ```

4. **Start PostgreSQL** (uses port 5433 to avoid conflicts with local PostgreSQL)
   ```bash
   docker compose up -d
   ```

   The default `.env` settings connect to the Docker PostgreSQL container automatically.

5. **Setup database**
   ```bash
   cd backend
   rails db:create db:migrate
   ```

6. **Configure API keys** (edit `.env` file created in step 3)
   ```bash
   # Database (defaults work with docker-compose)
   DATABASE_HOST=localhost
   DATABASE_PORT=5433
   DATABASE_USER=hypersense
   DATABASE_PASSWORD=hypersense_dev

   # For remote databases, use DATABASE_URL instead:
   # DATABASE_URL=postgresql://user:password@host:5432/hypersense

   # Required: Anthropic API key for AI reasoning
   ANTHROPIC_API_KEY=your_anthropic_api_key

   # Required: Hyperliquid credentials for trading
   HYPERLIQUID_PRIVATE_KEY=your_wallet_private_key
   HYPERLIQUID_ADDRESS=your_wallet_address

   # Optional: Override default LLM model
   LLM_MODEL=claude-sonnet-4-5
   ```

7. **Test data pipeline**
   ```bash
   rails runner "MarketSnapshotJob.perform_now"
   ```

8. **Run the server**
   ```bash
   bin/dev
   ```

9. **Start background jobs**
   ```bash
   bin/jobs
   ```

10. **Start the frontend** (new terminal)
    ```bash
    cd frontend
    npm install
    npm run dev
    ```

    The dashboard will be available at http://localhost:5173

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

### 1. Data Collection (MarketSnapshotJob - every minute)

Fetches prices from Binance API, calculates technical indicators, and stores market snapshots.

```ruby
# Trigger manually
MarketSnapshotJob.perform_now

# Example output:
# BTC: $97000.0 | RSI: 60.1 | MACD: 46.03
# ETH: $3200.0  | RSI: 66.0 | MACD: 1.98
# SOL: $190.0   | RSI: 45.0 | MACD: -0.0
# BNB: $700.0   | RSI: 60.1 | MACD: 0.68
```

**MarketSnapshot Model:**
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

### 2. Technical Indicators

Calculated during data collection by `Indicators::Calculator`:

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

### 3. Price Forecasting (ForecastJob - every 5 min)

Prophet-based ML predictions for multiple timeframes.

```ruby
# Generate forecasts for all assets
ForecastJob.perform_now

# Or use the predictor directly
predictor = Forecasting::PricePredictor.new("BTC")
forecasts = predictor.predict_all_timeframes
# => { "1m" => Forecast, "15m" => Forecast, "1h" => Forecast }

# Forecast model
forecast = Forecast.latest_for("BTC", "1h")
forecast.current_price      # => 97000.0
forecast.predicted_price    # => 97500.0
forecast.direction          # => "bullish" / "bearish" / "neutral"
forecast.predicted_change_pct # => 0.52

# Validate past predictions against actual prices
predictor.validate_past_forecasts
# Updates forecast records with actual_price, mae, mape
```

### 4. News & Whale Alerts (Real-time)

External signals for sentiment analysis and smart money tracking.

```ruby
# News from RSS feed (coinjournal.net)
fetcher = DataIngestion::NewsFetcher.new
news = fetcher.fetch
# => [{ title: "Bitcoin...", published_at: Time, symbols: ["BTC"], ... }]

# Filter news for specific assets
fetcher.fetch_for_symbols(["BTC", "ETH"])

# Whale alerts (whale-alert.io)
whale_fetcher = DataIngestion::WhaleAlertFetcher.new
alerts = whale_fetcher.fetch
# => [{ amount: "1,580 BTC", usd_value: "$138M", action: "transferred...", severity: 6, signal: :neutral }]

# Signal interpretation:
# - :potentially_bullish (stablecoin minted, exchange outflow)
# - :potentially_bearish (exchange inflow)
# - :neutral (general transfers)
```

### 5. Weighted Context System

LLM agents receive data with assigned weights for prioritization.

```ruby
# Context weights from settings.yml
weights = {
  forecast: 0.6,      # Price predictions (PRIMARY signal)
  sentiment: 0.2,     # Fear & Greed + News
  technical: 0.1,     # EMA, RSI, MACD, Pivots
  whale_alerts: 0.1   # Large capital movements
}

# Context assembler includes all weighted data
assembler = Reasoning::ContextAssembler.new(symbol: "BTC")
context = assembler.for_trading(macro_strategy: MacroStrategy.active)
# Includes: forecast, news, whale_alerts, market_data, technical_indicators, sentiment

# LLM system prompt instructs to weight inputs accordingly:
# "When data sources conflict, weight your decision according to these priorities."
```

### 6. Macro Strategy (MacroStrategyJob - daily at 6am)

High-level market analysis that sets the trading bias for the day.

```ruby
# Runs daily at 6am via MacroStrategyJob
strategy = Reasoning::HighLevelAgent.new.analyze

strategy.bias            # => "bullish" / "bearish" / "neutral"
strategy.risk_tolerance  # => 0.7 (scale 0.0-1.0)
strategy.market_narrative # => "Bitcoin showing strength above 50-day EMA..."
strategy.support_for("BTC")    # => [95000, 92000]
strategy.resistance_for("BTC") # => [100000, 105000]

# Check freshness
MacroStrategy.active       # => Current valid strategy
MacroStrategy.needs_refresh?  # => true if stale or missing
```

### 4. Trading Decisions (TradingCycleJob - every 5 min)

Low-level agent generates trade decisions for each asset within the macro bias.

```ruby
# Runs every 5 minutes via TradingCycleJob
agent = Reasoning::LowLevelAgent.new

# Single asset decision
decision = agent.decide(symbol: "BTC", macro_strategy: MacroStrategy.active)

decision.operation   # => "open" / "close" / "hold"
decision.direction   # => "long" / "short"
decision.confidence  # => 0.78
decision.leverage    # => 5
decision.stop_loss   # => 95000
decision.take_profit # => 105000
decision.actionable? # => true (confidence >= 0.6, not hold)

# All assets at once
decisions = agent.decide_all(macro_strategy: MacroStrategy.active)
# => [TradingDecision(BTC), TradingDecision(ETH), TradingDecision(SOL), TradingDecision(BNB)]
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
  "reasoning": "RSI neutral at 62, MACD bullish crossover, price above all EMAs"
}
```

### 5. Risk Validation

Decisions are validated before execution via `Risk::RiskManager`:

```ruby
# Centralized risk validation
risk_manager = Risk::RiskManager.new
result = risk_manager.validate(decision, entry_price: 100_000)
result.approved?           # => true/false
result.rejection_reason    # => "Confidence 0.5 below minimum 0.6"

# Risk-based position sizing
sizer = Risk::PositionSizer.new
result = sizer.calculate(
  entry_price: 100_000,
  stop_loss: 95_000,
  direction: "long"
)
result[:size]       # => 0.02 (BTC)
result[:risk_amount] # => 100 ($)
```

**Risk Configuration (`config/settings.yml`):**
```yaml
risk:
  max_position_size: 0.05        # 5% of capital max
  min_confidence: 0.6            # 60% confidence threshold
  max_leverage: 10               # Max leverage allowed
  default_leverage: 3            # Default leverage
  max_open_positions: 5          # Max concurrent positions
  max_risk_per_trade: 0.01       # 1% of capital at risk per trade
  min_risk_reward_ratio: 2.0     # Minimum R/R ratio (2:1)
  enforce_risk_reward_ratio: true # Reject below min R/R (false = warn only)
  max_daily_loss: 0.05           # 5% max daily loss (circuit breaker)
  max_consecutive_losses: 3      # Consecutive losses before halt
  circuit_breaker_cooldown: 24   # Hours to wait after trigger
```

### 6. Risk Monitoring (RiskMonitoringJob - every minute)

Continuous monitoring of open positions for SL/TP triggers and circuit breaker status.

**Stop-Loss / Take-Profit:**
```ruby
sl_manager = Risk::StopLossManager.new
results = sl_manager.check_all_positions
# => { triggered: [...], checked: 5, skipped: 1 }

# Position risk fields
position = Position.open.find_by(symbol: "BTC")
position.stop_loss_price      # => 95000
position.take_profit_price    # => 110000
position.risk_amount          # => 500 ($)
position.stop_loss_triggered?(94_000)  # => true
position.take_profit_triggered?        # => false
position.risk_reward_ratio    # => 3.0
position.stop_loss_distance_pct # => 5.0 (%)
```

**Circuit Breaker:**
```ruby
breaker = Risk::CircuitBreaker.new
breaker.trading_allowed?   # => true/false
breaker.record_loss(500)   # Record losing trade
breaker.record_win(200)    # Record winning trade (resets consecutive losses)
breaker.status             # => { trading_allowed: true, daily_loss: 500, ... }
```

### 7. Execution Layer (Paper Trading)

The execution layer is implemented with paper trading support. Real order placement requires enhancing the hyperliquid gem with write operations.

**Position Model:**
```ruby
# Track open positions
position = Position.open.find_by(symbol: "BTC")
position.direction       # => "long"
position.size           # => 0.1
position.entry_price    # => 100000
position.pnl_percent    # => 5.0 (%)
position.unrealized_pnl # => 500.0 (USD)
```

**Order Execution (Paper Trading):**
```ruby
# Execute a trading decision
executor = Execution::OrderExecutor.new
order = executor.execute(decision)

order.status           # => "filled" (simulated)
order.filled_size      # => 0.1
order.average_fill_price # => 100050
```

**Account Management:**
```ruby
manager = Execution::AccountManager.new

# Fetch account state from Hyperliquid
state = manager.fetch_account_state
state[:account_value]    # => 10000.0
state[:available_margin] # => 8000.0

# Check if can trade
manager.can_trade?(margin_required: 1000) # => true/false
```

**Position Sync from Hyperliquid:**
```ruby
pm = Execution::PositionManager.new

# Sync positions from exchange
pm.sync_from_hyperliquid
# => { created: 2, updated: 0, closed: 0 }

# Update prices
pm.update_prices
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

### Phase 3: Reasoning Engine ✅
- [x] MacroStrategy model (bias, risk tolerance, key levels)
- [x] TradingDecision model (operation, direction, confidence)
- [x] ContextAssembler (market data, indicators, sentiment)
- [x] HighLevelAgent (daily macro strategy via Claude Sonnet)
- [x] LowLevelAgent (5-min trade decisions via Claude Sonnet)
- [x] DecisionParser with dry-validation JSON schemas

### Phase 4: Hyperliquid Integration ✅
- [x] Position, Order, ExecutionLog models
- [x] HyperliquidClient (read operations via forked gem)
- [x] AccountManager (account state, margin calculations)
- [x] PositionManager (position sync, tracking)
- [x] OrderExecutor (paper trading mode)
- [x] TradingCycle integration
- [ ] Write operations (requires gem enhancement - see `docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md`)

### Phase 5: Risk Management ✅
- [x] Position sizing (risk-based, configurable max risk per trade)
- [x] Stop-loss / Take-profit (stored in Position, enforced by RiskMonitoringJob)
- [x] Circuit breakers (daily loss limits, consecutive loss limits, cooldown)
- [x] Risk/reward validation (configurable enforcement)
- [x] Centralized risk validation (Risk::RiskManager)
- [x] Paper trading mode (already implemented in Phase 4)

### Phase 5.1: Predictive Modeling & Weighted Context ✅
- [x] Weighted context system (forecast: 0.6, sentiment: 0.2, technical: 0.1, whale_alerts: 0.1)
- [x] Prophet-based price forecasting (1m, 15m, 1h predictions)
- [x] Forecast model with MAE/MAPE validation tracking
- [x] News fetcher (RSS from coinjournal.net)
- [x] Whale alert fetcher (whale-alert.io free endpoint)
- [x] Context assembler integration with all new data sources
- [x] LLM prompts updated with weight instructions

### Phase 6: Dashboard ✅
- [x] React frontend (Vite + TypeScript)
- [x] Equity curve (recharts)
- [x] Position tracking
- [x] Decision logs
- [x] ActionCable WebSocket real-time updates
- [x] API v1 controllers (dashboard, positions, decisions, market_data, macro_strategies)
- [x] Market overview with forecasts and indicators
- [x] System status monitoring
- [x] React Router with detail pages (decisions, strategies, forecasts, snapshots)
- [x] Reusable filter components (date range, symbol, status, search, pagination)
- [x] Paginated list endpoints with filters

### Phase 7: Production
- [ ] Dockerfile
- [ ] docker-compose.production.yml
- [ ] Monitoring/alerting

---

## Implementation Plan

### Completed Phases

**Phase 3: Multi-Agent Reasoning Engine** - See "Current Implementation" section for details.

**Phase 4: Hyperliquid Integration** - See "Current Implementation" section for details.
- Note: Write operations still require gem enhancement - see `docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md`

**Phase 5: Risk Management** - See "Current Implementation" section for details.

### Phase 6: React Dashboard (Completed)

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/dashboard` | GET | Aggregated dashboard data |
| `/api/v1/dashboard/account` | GET | Account summary |
| `/api/v1/dashboard/system_status` | GET | System health status |
| `/api/v1/positions` | GET | All positions (paginated) |
| `/api/v1/positions/open` | GET | Open positions with summary |
| `/api/v1/positions/performance` | GET | Equity curve and statistics |
| `/api/v1/decisions` | GET | Trading decisions (paginated) |
| `/api/v1/decisions/recent` | GET | Last N decisions |
| `/api/v1/decisions/stats` | GET | Decision statistics |
| `/api/v1/market_data/current` | GET | Current prices and indicators |
| `/api/v1/market_data/:symbol/history` | GET | Historical price data |
| `/api/v1/market_data/forecasts` | GET | Price forecasts (aggregated or paginated list) |
| `/api/v1/market_data/snapshots` | GET | Market snapshots (paginated with filters) |
| `/api/v1/macro_strategies` | GET | Macro strategies (paginated) |
| `/api/v1/macro_strategies/current` | GET | Active macro strategy |

**WebSocket Channels:**

```javascript
// Connect to dashboard channel for real-time updates
const subscription = cable.subscriptions.create("DashboardChannel", {
  received(data) {
    // data.type: market_update, position_update, decision_update, macro_strategy_update
    console.log(data);
  }
});

// Connect to markets channel for price updates
const markets = cable.subscriptions.create({ channel: "MarketsChannel", symbol: "BTC" }, {
  received(data) {
    console.log(data);
  }
});
```

**Dashboard Components:**

- **AccountSummary** - Open positions count, unrealized PnL, margin used, daily P&L
- **MarketOverview** - Current prices, RSI, MACD, EMA signals, forecasts for all assets
- **PositionsTable** - Open positions with entry price, current price, PnL, SL/TP
- **EquityCurve** - Cumulative PnL chart with win rate and statistics
- **MacroStrategyCard** - Current market bias, risk tolerance, narrative, key levels
- **DecisionLog** - Recent trading decisions with reasoning
- **SystemStatus** - Health status of market data, trading cycle, macro strategy

**Detail Pages (with React Router):**

| Route | Page | Features |
|-------|------|----------|
| `/` | Dashboard | Main dashboard with all cards |
| `/decisions` | DecisionsPage | Trading decisions with status, operation, symbol filters |
| `/macro-strategies` | MacroStrategiesPage | Strategy history with bias filter, expandable narrative |
| `/forecasts` | ForecastsPage | Price forecasts with symbol, timeframe, date filters |
| `/market-snapshots` | MarketSnapshotsPage | Market snapshots with RSI/MACD signals, expandable indicators |

**Filter Components:**

- **DateRangeFilter** - Date range with 24h, 7d, 30d presets
- **SymbolFilter** - Dropdown for BTC, ETH, SOL, BNB
- **StatusFilter** - Generic status/bias/operation dropdown
- **SearchFilter** - Debounced text search (300ms)
- **Pagination** - Page navigation with size selector
- **DataTable** - Generic table with loading skeleton, empty state, expandable rows

### Phase 7: Production (TODO)

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
