Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API v1 routes
  namespace :api do
    namespace :v1 do
      # Health check with version info
      get "health", to: "health#show"

      # Dashboard - aggregated data
      get "dashboard", to: "dashboard#index"
      get "dashboard/account", to: "dashboard#account"
      get "dashboard/system_status", to: "dashboard#system_status_endpoint"

      # Positions
      resources :positions, only: [ :index, :show ] do
        collection do
          get :open
          get :performance
        end
      end

      # Trading Decisions
      resources :decisions, only: [ :index, :show ] do
        collection do
          get :recent
          get :stats
        end
      end

      # Market Data
      get "market_data/current", to: "market_data#current"
      get "market_data/forecasts", to: "market_data#forecasts"
      get "market_data/snapshots", to: "market_data#snapshots"
      get "market_data/:symbol", to: "market_data#show", constraints: { symbol: /[A-Za-z]+/ }
      get "market_data/:symbol/history", to: "market_data#history", constraints: { symbol: /[A-Za-z]+/ }
      get "market_data/:symbol/forecasts", to: "market_data#symbol_forecasts", constraints: { symbol: /[A-Za-z]+/ }

      # Macro Strategies
      resources :macro_strategies, only: [ :index, :show ] do
        collection do
          get :current
        end
      end

      # Execution Logs
      resources :execution_logs, only: [ :index, :show ] do
        collection do
          get :stats
        end
      end
    end
  end

  # ActionCable mount point (for WebSocket connections)
  mount ActionCable.server => "/cable"
end
