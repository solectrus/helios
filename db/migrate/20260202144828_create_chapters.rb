class CreateChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :chapters do |t|
      t.references :configuration, null: false, foreign_key: true
      t.string :name, null: false
      t.json :data, default: {}, null: false

      t.timestamps
    end
    add_index :chapters, %i[configuration_id name], unique: true
  end
end
