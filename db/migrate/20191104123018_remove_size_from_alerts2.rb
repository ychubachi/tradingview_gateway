class RemoveSizeFromAlerts2 < ActiveRecord::Migration[5.0]
  def change
    remove_column :alerts, :size, :float
  end
end
