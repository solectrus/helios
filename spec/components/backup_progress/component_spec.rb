RSpec.describe BackupProgress::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(kind: :backup, include_s3: false, completion:)) }

  let(:backup) do
    Backup.create!(filename: 'solectrus-backup-20260508-110000.tar', bytes: 2_048, destination: 'local')
  end
  let(:completion) do
    BackupProgress::Completion.new(
      kind: :backup, status: :success, backup:, message: nil,
      started_at: Time.zone.local(2026, 5, 8, 10, 0, 0), finished_at: finished_at
    )
  end

  context 'with a run of a few seconds' do
    let(:finished_at) { Time.zone.local(2026, 5, 8, 10, 0, 42) }

    it 'reports the duration in seconds' do
      expect(rendered).to have_text('42s')
    end
  end

  context 'with a run of a few minutes' do
    let(:finished_at) { Time.zone.local(2026, 5, 8, 10, 3, 5) }

    it 'reports minutes and seconds' do
      expect(rendered).to have_text('3:05 min')
    end
  end

  # A first backup of a multi-year InfluxDB takes hours; the label must not
  # roll over into a wrong minute count.
  context 'with a run of several hours' do
    let(:finished_at) { Time.zone.local(2026, 5, 8, 12, 7, 9) }

    it 'reports hours, minutes and seconds' do
      expect(rendered).to have_text('2:07:09 h')
    end
  end
end
