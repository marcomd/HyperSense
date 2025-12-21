class CreateMarketSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :market_snapshots do |t|
      t.string :symbol, null: false
      t.decimal :price, precision: 20, scale: 8, null: false
      t.decimal :high_24h, precision: 20, scale: 8
      t.decimal :low_24h, precision: 20, scale: 8
      t.decimal :volume_24h, precision: 20, scale: 8
      t.decimal :price_change_pct_24h, precision: 10, scale: 4
      t.jsonb :indicators, default: {}
      t.jsonb :sentiment, default: {}
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :market_snapshots, :symbol
    add_index :market_snapshots, :captured_at
    add_index :market_snapshots, [:symbol, :captured_at], unique: true
  end
end
