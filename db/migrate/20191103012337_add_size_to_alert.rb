class AddSizeToAlert < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :size, :float
  end
end
