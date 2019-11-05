class RenameFromTickeridToTickerOnAlerts < ActiveRecord::Migration[5.0]
  def change
    rename_column :alerts, :tickerid, :ticker
  end
end
