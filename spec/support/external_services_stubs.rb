# frozen_string_literal: true

require "webmock/rspec"

# Default stubs for external services that should return empty/nil during tests
# unless explicitly recorded with VCR cassettes

RSpec.configure do |config|
  config.before(:each) do
    # Stub news feed to return empty RSS
    WebMock.stub_request(:get, %r{coinjournal\.net/news/feed})
           .to_return(
             status: 200,
             body: '<?xml version="1.0"?><rss version="2.0"><channel><title>Test</title></channel></rss>',
             headers: { "Content-Type" => "application/rss+xml" }
           )

    # Stub whale alerts to return empty data
    WebMock.stub_request(:get, %r{whale-alert\.io/data\.json})
           .to_return(
             status: 200,
             body: '{"alerts":[],"hodl":{},"prices":{}}',
             headers: { "Content-Type" => "application/json" }
           )
  end
end
