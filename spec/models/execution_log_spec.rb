# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExecutionLog do
  describe "associations" do
    it "belongs to loggable polymorphically" do
      position = create(:position)
      log = create(:execution_log, loggable: position)

      expect(log.loggable).to eq(position)
      expect(log.loggable_type).to eq("Position")
    end

    it "can belong to an Order" do
      order = create(:order)
      log = create(:execution_log, loggable: order)

      expect(log.loggable).to eq(order)
      expect(log.loggable_type).to eq("Order")
    end

    it "loggable is optional" do
      log = build(:execution_log, loggable: nil)
      expect(log).to be_valid
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      log = build(:execution_log)
      expect(log).to be_valid
    end

    it "requires action" do
      log = build(:execution_log, action: nil)
      expect(log).not_to be_valid
      expect(log.errors[:action]).to include("can't be blank")
    end

    it "requires action to be a valid value" do
      %w[place_order cancel_order modify_order sync_position sync_account].each do |valid_action|
        log = build(:execution_log, action: valid_action)
        expect(log).to be_valid
      end

      log = build(:execution_log, action: "invalid")
      expect(log).not_to be_valid
      expect(log.errors[:action]).to include("is not included in the list")
    end

    it "requires status" do
      log = build(:execution_log, status: nil)
      expect(log).not_to be_valid
      expect(log.errors[:status]).to include("can't be blank")
    end

    it "requires status to be success or failure" do
      %w[success failure].each do |valid_status|
        log = build(:execution_log, status: valid_status)
        expect(log).to be_valid
      end

      log = build(:execution_log, status: "invalid")
      expect(log).not_to be_valid
      expect(log.errors[:status]).to include("is not included in the list")
    end
  end

  describe "scopes" do
    describe ".successful" do
      it "returns only successful logs" do
        success_log = create(:execution_log, status: "success")
        _failure_log = create(:execution_log, :failure)

        expect(ExecutionLog.successful).to contain_exactly(success_log)
      end
    end

    describe ".failed" do
      it "returns only failed logs" do
        _success_log = create(:execution_log, status: "success")
        failure_log = create(:execution_log, :failure)

        expect(ExecutionLog.failed).to contain_exactly(failure_log)
      end
    end

    describe ".for_action" do
      it "filters by action type" do
        place_log = create(:execution_log, action: "place_order")
        _cancel_log = create(:execution_log, action: "cancel_order")

        expect(ExecutionLog.for_action("place_order")).to contain_exactly(place_log)
      end
    end

    describe ".recent" do
      it "orders by executed_at descending" do
        older = create(:execution_log, executed_at: 2.hours.ago)
        newer = create(:execution_log, executed_at: 1.hour.ago)

        expect(ExecutionLog.recent.first).to eq(newer)
        expect(ExecutionLog.recent.last).to eq(older)
      end
    end

    describe ".today" do
      it "returns logs from today" do
        today_log = create(:execution_log, executed_at: Time.current)
        _yesterday_log = create(:execution_log, executed_at: 1.day.ago)

        expect(ExecutionLog.today).to contain_exactly(today_log)
      end
    end
  end

  describe "class methods" do
    describe ".log_success!" do
      it "creates a successful log entry" do
        position = create(:position)
        request = { symbol: "BTC", action: "sync" }
        response = { positions: [] }

        log = ExecutionLog.log_success!(
          loggable: position,
          action: "sync_position",
          request_payload: request,
          response_payload: response
        )

        expect(log).to be_persisted
        expect(log.status).to eq("success")
        expect(log.loggable).to eq(position)
        expect(log.request_payload).to eq(request.stringify_keys)
        expect(log.response_payload).to eq(response.stringify_keys)
        expect(log.executed_at).to be_present
      end
    end

    describe ".log_failure!" do
      it "creates a failure log entry with error message" do
        order = create(:order)
        request = { order_id: "123" }
        error = "Connection timeout"

        log = ExecutionLog.log_failure!(
          loggable: order,
          action: "place_order",
          request_payload: request,
          error_message: error
        )

        expect(log).to be_persisted
        expect(log.status).to eq("failure")
        expect(log.loggable).to eq(order)
        expect(log.error_message).to eq(error)
        expect(log.executed_at).to be_present
      end
    end
  end

  describe "helper methods" do
    describe "#success?" do
      it "returns true when status is success" do
        log = build(:execution_log, status: "success")
        expect(log.success?).to be true
      end

      it "returns false when status is failure" do
        log = build(:execution_log, :failure)
        expect(log.success?).to be false
      end
    end

    describe "#failure?" do
      it "returns true when status is failure" do
        log = build(:execution_log, :failure)
        expect(log.failure?).to be true
      end

      it "returns false when status is success" do
        log = build(:execution_log, status: "success")
        expect(log.failure?).to be false
      end
    end

    describe "#duration_ms" do
      it "returns nil when response has no duration" do
        log = build(:execution_log, response_payload: {})
        expect(log.duration_ms).to be_nil
      end

      it "returns duration from response payload" do
        log = build(:execution_log, response_payload: { "duration_ms" => 150 })
        expect(log.duration_ms).to eq(150)
      end
    end
  end
end
