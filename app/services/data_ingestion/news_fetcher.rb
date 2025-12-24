# frozen_string_literal: true

module DataIngestion
  # Fetches crypto news from RSS feeds
  #
  # Uses Feedjira to parse RSS feeds and extract recent news items
  # relevant to configured trading assets.
  #
  # @example Fetch recent news
  #   fetcher = DataIngestion::NewsFetcher.new
  #   news = fetcher.fetch
  #   # => [{ title: "...", published_at: Time, link: "...", symbols: ["BTC"] }, ...]
  #
  class NewsFetcher
    RSS_URL = "https://coinjournal.net/news/feed"
    MAX_ITEMS = 20
    CACHE_DURATION = 5.minutes

    # Keywords to identify relevant news for each asset
    ASSET_KEYWORDS = {
      "BTC" => %w[bitcoin btc],
      "ETH" => %w[ethereum eth ether],
      "SOL" => %w[solana sol],
      "BNB" => %w[binance bnb]
    }.freeze

    # General crypto keywords
    CRYPTO_KEYWORDS = %w[crypto cryptocurrency market trading bull bear rally crash pump dump].freeze

    def initialize
      @logger = Rails.logger
      @cache_key = "news_fetcher:#{RSS_URL}"
    end

    # Fetch and parse news from RSS feed
    # @return [Array<Hash>] Array of news items
    def fetch
      cached = Rails.cache.read(@cache_key)
      return cached if cached

      news_items = fetch_from_feed
      Rails.cache.write(@cache_key, news_items, expires_in: CACHE_DURATION)
      news_items
    rescue StandardError => e
      @logger.error "[NewsFetcher] Error fetching news: #{e.message}"
      []
    end

    # Fetch news filtered for specific symbols
    # @param symbols [Array<String>] Asset symbols to filter for
    # @return [Array<Hash>] Filtered news items
    def fetch_for_symbols(symbols = Settings.assets.to_a)
      all_news = fetch
      return [] if all_news.empty?

      all_news.select do |item|
        # Include if news mentions any of the requested symbols
        (item[:symbols] & symbols).any? ||
          # Or if it's general crypto news (potentially relevant to all)
          item[:is_general_crypto]
      end
    end

    # Get recent news for context assembly (last 5 items)
    # @return [Array<Hash>] Recent news items
    def recent_news(limit: 5)
      fetch.first(limit)
    end

    private

    def fetch_from_feed
      @logger.info "[NewsFetcher] Fetching news from #{RSS_URL}"

      feed = Feedjira.parse(fetch_rss_content)
      return [] unless feed&.entries

      feed.entries.first(MAX_ITEMS).map do |entry|
        parse_entry(entry)
      end.compact
    rescue Feedjira::NoParserAvailable => e
      @logger.error "[NewsFetcher] Failed to parse feed: #{e.message}"
      []
    end

    def fetch_rss_content
      response = Faraday.get(RSS_URL) do |req|
        req.options.timeout = 10
        req.options.open_timeout = 5
        req.headers["User-Agent"] = "HyperSense Trading Agent"
      end

      raise "HTTP #{response.status}" unless response.success?

      response.body
    end

    def parse_entry(entry)
      title = entry.title&.strip || ""
      summary = entry.summary&.strip || entry.content&.strip || ""
      full_text = "#{title} #{summary}".downcase

      # Identify which assets this news relates to
      symbols = identify_symbols(full_text)

      # Check if it's general crypto news
      is_general = symbols.empty? && CRYPTO_KEYWORDS.any? { |kw| full_text.include?(kw) }

      {
        title: title,
        summary: truncate_summary(summary),
        published_at: entry.published || entry.updated,
        link: entry.url || entry.id,
        symbols: symbols,
        is_general_crypto: is_general
      }
    end

    def identify_symbols(text)
      ASSET_KEYWORDS.filter_map do |symbol, keywords|
        symbol if keywords.any? { |kw| text.include?(kw) }
      end
    end

    def truncate_summary(summary, max_length: 200)
      return "" if summary.blank?

      # Strip HTML tags
      clean = ActionView::Base.full_sanitizer.sanitize(summary)
      clean.truncate(max_length)
    end
  end
end
