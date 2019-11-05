class AddExchangeToAlert < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :exchange, :string
  end
end
