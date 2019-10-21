class AddRealSizeToAlerts < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :size, :real
  end
end
