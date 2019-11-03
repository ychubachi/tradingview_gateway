class AddProfitAndLossAndRiskToAlerts < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :profit, :float
    add_column :alerts, :loss, :float
    add_column :alerts, :risk, :float
  end
end
