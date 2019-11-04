class AddQtyToAlerts < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :qty, :float
  end
end
