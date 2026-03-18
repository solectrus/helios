class DropConfigurationAndChapterTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :chapters
    drop_table :configurations
  end

  def down
    create_table :configurations do |t|
      t.json :data, default: {}, null: false
      t.timestamps
    end

    create_table :chapters do |t|
      t.references :configuration, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.json :data, default: {}, null: false
      t.timestamps
    end

    add_index :chapters, %i[configuration_id kind name], unique: true
  end
end
