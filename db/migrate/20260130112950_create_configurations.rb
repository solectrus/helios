class CreateConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :configurations do |t|
      t.json :data, null: false, default: {}

      t.timestamps
    end
  end
end
