class RemoveBodyFromAlert < ActiveRecord::Migration[5.0]
  def change
    remove_column :alerts, :body, :string
  end
end
