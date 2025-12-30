# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  # Create a concrete test job class
  let(:test_job) do
    Class.new(ApplicationJob) do
      self.queue_adapter = :test

      def perform
        true
      end
    end.new
  end

  let(:mock_connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
  let(:mock_pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool) }

  describe "#ensure_database_connection" do
    before do
      allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
      allow(ActiveRecord::Base).to receive(:connection_pool).and_return(mock_pool)
      allow(mock_pool).to receive(:flush!)
    end

    context "when connection is active" do
      before do
        allow(mock_connection).to receive(:active?).and_return(true)
      end

      it "does not attempt to reconnect" do
        expect(mock_connection).not_to receive(:reconnect!)

        test_job.send(:ensure_database_connection)
      end

      it "flushes the connection pool" do
        expect(mock_pool).to receive(:flush!)

        test_job.send(:ensure_database_connection)
      end
    end

    context "when connection is stale" do
      before do
        allow(mock_connection).to receive(:active?).and_return(false)
        allow(mock_connection).to receive(:reconnect!)
      end

      it "reconnects the database connection" do
        expect(mock_connection).to receive(:reconnect!)

        test_job.send(:ensure_database_connection)
      end

      it "logs a warning about reconnecting" do
        allow(Rails.logger).to receive(:warn)

        test_job.send(:ensure_database_connection)

        expect(Rails.logger).to have_received(:warn).with(/Reconnecting stale database connection/)
      end

      it "still flushes the connection pool" do
        expect(mock_pool).to receive(:flush!)

        test_job.send(:ensure_database_connection)
      end
    end

    context "when connection check fails" do
      before do
        allow(mock_connection).to receive(:active?).and_raise(PG::ConnectionBad, "Connection refused")
      end

      it "raises ActiveRecord::ConnectionNotEstablished" do
        expect { test_job.send(:ensure_database_connection) }
          .to raise_error(ActiveRecord::ConnectionNotEstablished, /Connection refused/)
      end

      it "logs an error" do
        allow(Rails.logger).to receive(:error)

        test_job.send(:ensure_database_connection) rescue nil

        expect(Rails.logger).to have_received(:error).with(/Database connection check failed.*PG::ConnectionBad/)
      end
    end

    context "when reconnect fails" do
      before do
        allow(mock_connection).to receive(:active?).and_return(false)
        allow(mock_connection).to receive(:reconnect!).and_raise(PG::ConnectionBad, "Cannot reconnect")
      end

      it "raises ActiveRecord::ConnectionNotEstablished" do
        expect { test_job.send(:ensure_database_connection) }
          .to raise_error(ActiveRecord::ConnectionNotEstablished, /Cannot reconnect/)
      end
    end
  end

  describe "retry configuration" do
    it "retries on ActiveRecord::ConnectionNotEstablished" do
      handler_keys = described_class.rescue_handlers.map(&:first)

      expect(handler_keys).to include("ActiveRecord::ConnectionNotEstablished")
    end

    it "retries on PG::ConnectionBad" do
      handler_keys = described_class.rescue_handlers.map(&:first)

      expect(handler_keys).to include("PG::ConnectionBad")
    end
  end

  describe "before_perform callback" do
    it "registers ensure_database_connection as a before_perform callback" do
      callbacks = described_class._perform_callbacks.select { |c| c.kind == :before }
      callback_filters = callbacks.map(&:filter)

      expect(callback_filters).to include(:ensure_database_connection)
    end
  end
end
