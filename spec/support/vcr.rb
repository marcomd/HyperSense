# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") do
    Rails.application.credentials.dig(:anthropic, :api_key)
  end

  # Allow localhost connections for test database
  config.ignore_localhost = true

  # External data sources (news, whale alerts) are stubbed in
  # spec/support/external_services_stubs.rb by default

  # Default cassette options
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [ :method, :uri, :body ]
  }
end
