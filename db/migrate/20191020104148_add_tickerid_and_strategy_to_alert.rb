class AddTickeridAndStrategyToAlert < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :tickerid, :string
    add_column :alerts, :strategy, :string
  end
end
