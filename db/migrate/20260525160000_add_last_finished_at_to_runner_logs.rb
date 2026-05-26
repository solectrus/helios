class AddLastFinishedAtToRunnerLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_logs, :last_finished_at, :datetime
  end
end
