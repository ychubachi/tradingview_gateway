class AddSizeToAlerts < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :size, :integer
  end
end
