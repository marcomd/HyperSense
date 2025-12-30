# frozen_string_literal: true

# Base class for all background jobs
#
# Provides:
# - Database connection health checking before job execution
# - Automatic retry on database connection errors
# - Stale connection cleanup
#
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Retry on database connection errors (prevents crashes from stale connections)
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  retry_on PG::ConnectionBad, wait: 5.seconds, attempts: 3

  # Check database connection health before each job execution
  before_perform :ensure_database_connection

  private

  # Ensure database connections are healthy before job execution
  #
  # Prevents pg gem segfaults on stale connections by:
  # 1. Checking if the primary connection is active
  # 2. Reconnecting if the connection is stale
  # 3. Flushing dead connections from the pool
  #
  # @return [void]
  # @raise [ActiveRecord::ConnectionNotEstablished] if connection cannot be established
  def ensure_database_connection
    connection = ActiveRecord::Base.connection

    unless connection.active?
      Rails.logger.warn "[#{self.class.name}] Reconnecting stale database connection"
      connection.reconnect!
    end

    # Clear any stale connections from the pool
    ActiveRecord::Base.connection_pool.flush!
  rescue StandardError => e
    Rails.logger.error "[#{self.class.name}] Database connection check failed: #{e.class} - #{e.message}"
    # Re-raise to trigger retry mechanism
    raise ActiveRecord::ConnectionNotEstablished, "Database connection failed: #{e.message}"
  end
end
