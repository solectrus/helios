class AddKindToChapters < ActiveRecord::Migration[8.1]
  def up
    add_column :chapters, :kind, :string

    # Migrate existing data: old `name` becomes `kind`,
    # singletons get their kind as display name, devices keep old name
    execute <<~SQL.squish
      UPDATE chapters SET kind = name
    SQL

    change_column_null :chapters, :kind, false

    remove_index :chapters, %i[configuration_id name]
    add_index :chapters,
              %i[configuration_id kind name],
              unique: true
  end

  def down
    remove_index :chapters, %i[configuration_id kind name]
    add_index :chapters,
              %i[configuration_id name],
              unique: true

    remove_column :chapters, :kind
  end
end
