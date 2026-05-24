RSpec.describe BackupsHelper do
  describe '#backup_in_progress_label' do
    let(:filename) { 'solectrus-backup-20260508-100000.tar' }

    it 'returns the generic in-progress label for the :running phase' do
      in_progress = BackupRepository::InProgress.new(started_at: Time.current, filename: filename)

      expect(helper.backup_in_progress_label(in_progress)).to eq(I18n.t('backups.index.in_progress'))
    end

    it 'returns an uploading label with a rounded percentage for the :uploading phase' do
      in_progress = BackupRepository::InProgress.new(
        started_at: Time.current, filename: filename,
        phase: :uploading, progress: 0.42
      )

      expect(helper.backup_in_progress_label(in_progress)).to eq(
        I18n.t('backups.index.phase_uploading',
               percent: helper.number_to_percentage(42, precision: 0)),
      )
    end

    it 'falls back to 0%% when progress is nil during :uploading' do
      in_progress = BackupRepository::InProgress.new(
        started_at: Time.current, filename: filename,
        phase: :uploading, progress: nil
      )

      expect(helper.backup_in_progress_label(in_progress)).to include('0')
    end
  end
end
