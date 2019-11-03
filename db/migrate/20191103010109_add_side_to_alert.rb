class AddSideToAlert < ActiveRecord::Migration[5.0]
  def change
    add_column :alerts, :side, :string
  end
end
