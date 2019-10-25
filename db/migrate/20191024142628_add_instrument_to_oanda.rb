class AddInstrumentToOanda < ActiveRecord::Migration[5.0]
  def change
    add_column :oandas, :instrument, :string
  end
end
