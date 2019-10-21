class RemoveSizeFromAlerts < ActiveRecord::Migration[5.0]
  def change
    remove_column :alerts, :size, :integer
  end
end
