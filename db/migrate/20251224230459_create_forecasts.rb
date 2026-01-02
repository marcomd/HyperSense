# frozen_string_literal: true

class CreateForecasts < ActiveRecord::Migration[8.1]
  def change
    create_table :forecasts do |t|
      t.string :symbol, null: false
      t.string :timeframe, null: false # "1m", "15m", "1h"
      t.decimal :predicted_price, precision: 20, scale: 8, null: false
      t.decimal :current_price, precision: 20, scale: 8, null: false
      t.decimal :actual_price, precision: 20, scale: 8 # filled later when validating
      t.decimal :mae, precision: 10, scale: 6 # mean absolute error, calculated after validation
      t.decimal :mape, precision: 10, scale: 4 # mean absolute percentage error
      t.datetime :forecast_for, null: false # target timestamp for the prediction

      t.timestamps
    end

    add_index :forecasts, :symbol
    add_index :forecasts, :timeframe
    add_index :forecasts, :forecast_for
    add_index :forecasts, [ :symbol, :timeframe, :forecast_for ], unique: true
    add_index :forecasts, [ :symbol, :timeframe ], name: "index_forecasts_on_symbol_and_timeframe"
  end
end
