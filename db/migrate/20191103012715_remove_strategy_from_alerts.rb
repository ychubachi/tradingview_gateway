class RemoveStrategyFromAlerts < ActiveRecord::Migration[5.0]
  def change
    remove_column :alerts, :strategy, :string
  end
end
