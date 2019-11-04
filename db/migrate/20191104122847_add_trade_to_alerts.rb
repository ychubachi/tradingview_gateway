class AddTradeToAlerts < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :trade, :string
  end
end
