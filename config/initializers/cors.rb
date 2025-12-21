# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Development: Allow React dev server
    origins "localhost:3000", "localhost:5173", "127.0.0.1:3000", "127.0.0.1:5173"

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true
  end

  # Production: Configure via environment variable
  if ENV["FRONTEND_URL"].present?
    allow do
      origins ENV["FRONTEND_URL"]

      resource "*",
        headers: :any,
        methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
        credentials: true
    end
  end
end
