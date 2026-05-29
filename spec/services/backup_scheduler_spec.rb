RSpec.describe BackupScheduler do
  # 03:00 schedule, evaluated at 03:30 the same day
  let(:now) { Time.zone.local(2026, 5, 29, 3, 30, 0) }
  let(:today) { Date.new(2026, 5, 29) }
  let(:yesterday) { Date.new(2026, 5, 28) }
  let(:enabled_config) { { 'schedule_enabled' => true, 'schedule_time' => '03:00' } }

  describe '.due?' do
    it 'is false when scheduling is disabled' do
      expect(described_class.due?(now:, config: { 'schedule_enabled' => false, 'schedule_time' => '03:00' },
                                  last_handled_on: nil)).to be(false)
    end

    it 'is false when the config section is blank' do
      expect(described_class.due?(now:, config: {}, last_handled_on: nil)).to be(false)
    end

    it 'is false before the scheduled time' do
      before = Time.zone.local(2026, 5, 29, 2, 59, 0)
      expect(described_class.due?(now: before, config: enabled_config, last_handled_on: nil)).to be(false)
    end

    it 'is true after the scheduled time when never handled' do
      expect(described_class.due?(now:, config: enabled_config, last_handled_on: nil)).to be(true)
    end

    it 'is true after the scheduled time when last handled on a previous day' do
      expect(described_class.due?(now:, config: enabled_config, last_handled_on: yesterday)).to be(true)
    end

    it 'is false once the day has already been handled' do
      expect(described_class.due?(now:, config: enabled_config, last_handled_on: today)).to be(false)
    end

    it 'is false for an unparseable time' do
      expect(described_class.due?(now:, config: { 'schedule_enabled' => true, 'schedule_time' => 'nonsense' },
                                  last_handled_on: nil)).to be(false)
    end

    it 'is false for an out-of-range time' do
      expect(described_class.due?(now:, config: { 'schedule_enabled' => true, 'schedule_time' => '25:00' },
                                  last_handled_on: nil)).to be(false)
    end

    it 'accepts a string "true" for schedule_enabled' do
      expect(described_class.due?(now:, config: { 'schedule_enabled' => 'true', 'schedule_time' => '03:00' },
                                  last_handled_on: nil)).to be(true)
    end
  end

  describe '.scheduled_time_label' do
    it 'returns the configured time when enabled and valid' do
      expect(described_class.scheduled_time_label(enabled_config)).to eq('03:00')
    end

    it 'returns nil when disabled' do
      expect(described_class.scheduled_time_label('schedule_enabled' => false, 'schedule_time' => '03:00')).to be_nil
    end

    it 'returns nil for an invalid time' do
      expect(described_class.scheduled_time_label('schedule_enabled' => true, 'schedule_time' => 'oops')).to be_nil
    end
  end

  describe '.tick' do
    let(:data_path) { Dir.mktmpdir }

    before do
      allow(Rails.configuration).to receive(:data_path).and_return(data_path)
      described_class.send(:tick_gate).make_false
      allow(described_class).to receive(:due?).and_return(true)
      allow(BackupRunner).to receive_messages(unavailable_reason: nil, in_progress: nil, start: true)
      allow(Orchestration::HeliosOperationBroadcaster).to receive(:broadcast!)
    end

    after { FileUtils.remove_entry(data_path) }

    it 'starts an automatic backup when due and nothing blocks it' do
      described_class.tick
      expect(BackupRunner).to have_received(:start).with(automatic: true)
    end

    it 'broadcasts after starting so open /backups views morph into the in-progress state' do
      described_class.tick
      expect(Orchestration::HeliosOperationBroadcaster).to have_received(:broadcast!)
    end

    it 'does not broadcast when a precondition blocks the backup' do
      allow(BackupRunner).to receive(:unavailable_reason).and_return('Databases not running')
      described_class.tick
      expect(Orchestration::HeliosOperationBroadcaster).not_to have_received(:broadcast!)
    end

    it 'does not start a backup when not due' do
      allow(described_class).to receive(:due?).and_return(false)
      described_class.tick
      expect(BackupRunner).not_to have_received(:start)
    end

    it 'marks the day handled even when a precondition is unmet, so it does not retry' do
      allow(BackupRunner).to receive(:unavailable_reason).and_return('Databases not running')

      described_class.tick

      aggregate_failures do
        expect(BackupRunner).not_to have_received(:start)
        expect(described_class.last_handled_date).to eq(Time.now.getlocal.to_date)
      end
    end

    it 'skips a tick when one is already running (atomic gate held)' do
      described_class.send(:tick_gate).make_true

      described_class.tick

      expect(BackupRunner).not_to have_received(:start)
    end

    it 'releases the gate after a tick so the next one can run' do
      described_class.tick
      described_class.tick
      expect(described_class.send(:tick_gate).false?).to be(true)
    end

    it 'swallows BackupRunner errors so the thread survives' do
      allow(BackupRunner).to receive(:start).and_raise(BackupRunner::Error, 'boom')
      expect { described_class.tick }.not_to raise_error
    end
  end

  describe '.last_handled_date' do
    let(:data_path) { Dir.mktmpdir }

    before { allow(Rails.configuration).to receive(:data_path).and_return(data_path) }
    after { FileUtils.remove_entry(data_path) }

    it 'is nil when no backup has been scheduled yet' do
      expect(described_class.last_handled_date).to be_nil
    end

    it 'round-trips the handled date through the state file' do
      described_class.send(:mark_handled!, Date.new(2026, 5, 29))
      expect(described_class.last_handled_date).to eq(Date.new(2026, 5, 29))
    end
  end

  describe '.reschedule!' do
    let(:data_path) { Dir.mktmpdir }
    let(:now) { Time.zone.local(2026, 5, 29, 9, 0, 0) }

    before { allow(Rails.configuration).to receive(:data_path).and_return(data_path) }
    after { FileUtils.remove_entry(data_path) }

    it 'runs today when the new time is still ahead (clears the marker)' do
      described_class.send(:mark_handled!, now.to_date)

      described_class.reschedule!(now:, config: { 'schedule_enabled' => true, 'schedule_time' => '10:00' })

      expect(described_class.last_handled_date).to be_nil
    end

    it 'waits until tomorrow when the new time has already passed today' do
      described_class.reschedule!(now:, config: { 'schedule_enabled' => true, 'schedule_time' => '03:00' })

      # Today is marked handled, so due? only fires again tomorrow at 03:00.
      aggregate_failures do
        expect(described_class.last_handled_date).to eq(now.to_date)
        expect(described_class.due?(now:, config: { 'schedule_enabled' => true, 'schedule_time' => '03:00' }))
          .to be(false)
      end
    end

    it 'clears the marker when scheduling is disabled' do
      described_class.send(:mark_handled!, now.to_date)

      described_class.reschedule!(now:, config: { 'schedule_enabled' => false, 'schedule_time' => '03:00' })

      expect(described_class.last_handled_date).to be_nil
    end
  end
end
