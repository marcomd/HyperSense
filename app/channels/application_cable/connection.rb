# frozen_string_literal: true

module ApplicationCable
  # WebSocket connection handler
  # For now, allows all connections (no authentication required for dashboard)
  class Connection < ActionCable::Connection::Base
    identified_by :connection_id

    def connect
      self.connection_id = SecureRandom.uuid
      logger.info "WebSocket connected: #{connection_id}"
    end

    def disconnect
      logger.info "WebSocket disconnected: #{connection_id}"
    end
  end
end
