source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# Use postgresql as the database for Active Record
# Pin to 1.5.x due to segfault bugs in 1.6.x on macOS ARM64 with Ruby 3.4
gem "pg", "~> 1.5.0"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Load environment variables from .env (must be loaded early)
gem "dotenv-rails", groups: [ :development, :test ]

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# HyperSense Core Dependencies
gem "ruby_llm"               # LLM-agnostic SDK (Anthropic, Gemini, Ollama, etc.)
gem "faraday"                # HTTP client for API calls
gem "oj"                     # Fast JSON parsing
gem "feedjira"               # RSS feed parsing
gem "eth"                    # Ethereum utilities (EIP-712 signing for Hyperliquid)
gem "config"                 # Settings management (config/settings.yml)
gem "dry-validation"         # Input validation
gem "prophet-rb"             # Time series forecasting (Meta Prophet)

# Hyperliquid DEX client (forked for write operations)
gem "hyperliquid", github: "marcomd/hyperliquid", branch: "feature/add-eip-712-signing-and-exchange-operations"

# Solid Queue Web UI (disabled for API-only mode - enable when adding admin UI)
# gem "mission_control-jobs"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug" # , platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "webmock"             # Mock HTTP requests
  gem "vcr"                 # Record HTTP interactions
end
