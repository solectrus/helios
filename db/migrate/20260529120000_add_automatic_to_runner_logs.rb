class AddAutomaticToRunnerLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_logs, :automatic, :boolean, null: false, default: false
  end
end
