class CreateOandas < ActiveRecord::Migration[5.0]
  def change
    create_table :oandas do |t|
      t.string :strategy
      t.float :qty

      t.timestamps
    end
  end
end
