# frozen_string_literal: true

class CreateExecutionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :execution_logs do |t|
      t.references :loggable, polymorphic: true, null: true
      t.string :action, null: false
      t.string :status, null: false
      t.jsonb :request_payload, default: {}
      t.jsonb :response_payload, default: {}
      t.text :error_message
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :execution_logs, :action
    add_index :execution_logs, :status
    add_index :execution_logs, :executed_at
    add_index :execution_logs, [ :loggable_type, :loggable_id ]
  end
end
