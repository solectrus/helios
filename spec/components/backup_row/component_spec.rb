RSpec.describe BackupRow::Component, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(backup:, restore_in_progress:, actions_disabled_reason: nil))
  end

  let(:backup) do
    Backup.create!(
      filename: 'solectrus-backup-20260508-110000.tar',
      created_at: Time.zone.local(2026, 5, 8, 11, 0, 0),
      bytes: 1024,
      destination: 'local',
      files: [{ 'name' => 'helios/config.yaml', 'bytes' => 154 }],
    )
  end
  let(:restore_in_progress) { nil }

  it 'shows the backup timestamp' do
    expect(rendered).to have_text('11:00')
  end

  context 'when this backup is being restored' do
    let(:restore_in_progress) do
      BackupRepository::InProgress.new(
        started_at: Time.current, filename: backup.filename, phase: :downloading, progress: 0.42,
      )
    end

    it 'shows the live phase label instead of the actions' do
      expect(rendered).to have_text(I18n.t('backups.index.phase_downloading', percent: 42))
    end
  end
end
