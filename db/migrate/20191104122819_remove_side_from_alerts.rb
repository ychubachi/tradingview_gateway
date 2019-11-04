class RemoveSideFromAlerts < ActiveRecord::Migration[5.0]
  def change
    remove_column :alerts, :side, :string
  end
end
