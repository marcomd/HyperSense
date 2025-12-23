# frozen_string_literal: true

# Audit trail for all execution operations
#
# Logs all interactions with Hyperliquid API including order placement,
# cancellation, position syncs, and account queries. Used for debugging,
# compliance, and performance monitoring.
#
# == Schema Information
#
# Table name: execution_logs
#
#  id               :bigint           not null, primary key
#  loggable_type    :string
#  loggable_id      :bigint
#  action           :string           not null
#  status           :string           not null (success/failure)
#  request_payload  :jsonb            default({})
#  response_payload :jsonb            default({})
#  error_message    :text
#  executed_at      :datetime         not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class ExecutionLog < ApplicationRecord
  VALID_ACTIONS = %w[place_order cancel_order modify_order sync_position sync_account].freeze
  VALID_STATUSES = %w[success failure].freeze

  # Associations
  belongs_to :loggable, polymorphic: true, optional: true

  # Validations
  validates :action, presence: true, inclusion: { in: VALID_ACTIONS }
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :executed_at, presence: true

  # Callbacks
  before_validation :set_executed_at, on: :create

  # Scopes
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failure") }
  scope :for_action, ->(action) { where(action: action) }
  scope :recent, -> { order(executed_at: :desc) }
  scope :today, -> { where(executed_at: Time.current.beginning_of_day..) }

  # Class methods

  # Log a successful operation
  # @param loggable [ActiveRecord::Base, nil] Associated record
  # @param action [String] Action type
  # @param request_payload [Hash] Request data
  # @param response_payload [Hash] Response data
  # @return [ExecutionLog]
  def self.log_success!(loggable:, action:, request_payload: {}, response_payload: {})
    create!(
      loggable: loggable,
      action: action,
      status: "success",
      request_payload: request_payload,
      response_payload: response_payload,
      executed_at: Time.current
    )
  end

  # Log a failed operation
  # @param loggable [ActiveRecord::Base, nil] Associated record
  # @param action [String] Action type
  # @param request_payload [Hash] Request data
  # @param error_message [String] Error description
  # @param response_payload [Hash] Optional response data
  # @return [ExecutionLog]
  def self.log_failure!(loggable:, action:, request_payload: {}, error_message:, response_payload: {})
    create!(
      loggable: loggable,
      action: action,
      status: "failure",
      request_payload: request_payload,
      response_payload: response_payload,
      error_message: error_message,
      executed_at: Time.current
    )
  end

  # Status helpers

  def success?
    status == "success"
  end

  def failure?
    status == "failure"
  end

  # Response accessors

  # Get duration from response payload if available
  # @return [Integer, nil] Duration in milliseconds
  def duration_ms
    response_payload&.dig("duration_ms")
  end

  private

  def set_executed_at
    self.executed_at ||= Time.current
  end
end
