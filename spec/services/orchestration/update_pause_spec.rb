RSpec.describe Orchestration::UpdatePause do
  include ActiveSupport::Testing::TimeHelpers

  before do
    with_config_yaml

    allow(Orchestration::Runner).to receive(:pause)
    allow(Orchestration::Runner).to receive(:unpause)
    allow(Orchestration::Container).to receive(:invalidate_cache)
    allow(Orchestration::Container).to receive(:find).and_return(watchtower)

    # No operation in flight unless a test says otherwise.
    allow(CsvImportRunner).to receive(:in_progress?).and_return(false)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
  end

  after { Orchestration::PendingOperations.clear_all }

  # One stub serves both halves of the cycle: `pause!` asks whether Watchtower
  # runs, `resume_if_idle!` whether it is paused. A real container is never
  # both, but no example exercises the contradiction.
  let(:watchtower) do
    instance_double(Orchestration::Container, running?: true, status: 'paused')
  end

  def marker_path
    File.join(config_yaml_dir, 'helios', 'watchtower_pause.json')
  end

  describe '.pause!' do
    it 'freezes Watchtower and records the reason' do
      described_class.pause!(:backup)

      expect(Orchestration::Runner).to have_received(:pause).with('watchtower')
      expect(described_class).to be_paused
      expect(JSON.parse(File.read(marker_path))).to include('reason' => 'backup')
    end

    it 'does nothing when Watchtower is not running' do
      allow(watchtower).to receive(:running?).and_return(false)

      described_class.pause!(:backup)

      expect(Orchestration::Runner).not_to have_received(:pause)
      expect(described_class).not_to be_paused
    end

    it 'does nothing when Watchtower is not part of the stack' do
      allow(Orchestration::Container).to receive(:find).and_return(nil)

      described_class.pause!(:backup)

      expect(Orchestration::Runner).not_to have_received(:pause)
      expect(described_class).not_to be_paused
    end

    it 'keeps the original reason when already paused' do
      described_class.pause!(:backup)
      described_class.pause!(:csv_import)

      expect(Orchestration::Runner).to have_received(:pause).once
      expect(JSON.parse(File.read(marker_path))).to include('reason' => 'backup')
    end

    # `docker pause` fires an event that has StackStatus recompute at once. A
    # marker written afterwards would arrive too late, and that recompute would
    # count Watchtower as a plain stopped service — the whole stack amber for
    # the duration of every nightly backup.
    it 'records the marker before freezing the container' do
      allow(Orchestration::Runner).to receive(:pause) do
        expect(described_class).to be_paused
      end

      described_class.pause!(:backup)

      expect(Orchestration::Runner).to have_received(:pause)
    end

    it 'swallows failures so the guarded operation still runs' do
      allow(watchtower).to receive(:status).and_return('running')
      allow(Orchestration::Runner).to receive(:pause).and_raise(Orchestration::Runner::CommandError, 'boom')

      expect { described_class.pause!(:backup) }.not_to raise_error
      expect(described_class).not_to be_paused
    end

    # The other half of that failure: the container did freeze and the command
    # reported an error anyway. Dropping the marker here would strand it —
    # resume_if_idle! bails out on a missing marker, so nothing would ever
    # thaw Watchtower again.
    it 'keeps the marker when the failed pause froze Watchtower anyway' do
      allow(Orchestration::Runner).to receive(:pause).and_raise(Orchestration::Runner::CommandError, 'boom')

      described_class.pause!(:backup)

      expect(described_class).to be_paused
    end

    it 'keeps the marker when the failure leaves the state unreadable' do
      allow(Orchestration::Runner).to receive(:pause).and_raise(Orchestration::Runner::CommandError, 'boom')
      # First call answers "is Watchtower running?", the one from the rescue
      # then hits the same Docker outage that made the pause fail.
      lookups = 0
      allow(Orchestration::Container).to receive(:find) do
        lookups += 1
        raise Orchestration::Container::ConnectionError, 'docker gone' if lookups > 1

        watchtower
      end

      expect { described_class.pause!(:backup) }.not_to raise_error
      expect(described_class).to be_paused
    end
  end

  describe '.resume_if_idle!' do
    it 'does nothing when there is no pause' do
      described_class.resume_if_idle!

      expect(Orchestration::Runner).not_to have_received(:unpause)
    end

    it 'brings Watchtower back when no operation is in flight' do
      described_class.pause!(:backup)

      described_class.resume_if_idle!

      expect(Orchestration::Runner).to have_received(:unpause).with('watchtower')
      expect(described_class).not_to be_paused
    end

    # `docker compose unpause` errors on a container that is not paused, which
    # would strand the marker and have every following sweep retry it.
    it 'drops the marker without unpausing a Watchtower that was recreated' do
      described_class.pause!(:backup)
      allow(watchtower).to receive(:status).and_return('running')

      described_class.resume_if_idle!

      aggregate_failures do
        expect(Orchestration::Runner).not_to have_received(:unpause)
        expect(described_class).not_to be_paused
      end
    end

    it 'keeps the pause while the CSV import runs' do
      described_class.pause!(:csv_import)
      allow(CsvImportRunner).to receive(:in_progress?).and_return(true)

      described_class.resume_if_idle!

      expect(Orchestration::Runner).not_to have_received(:unpause)
      expect(described_class).to be_paused
    end

    it 'keeps the pause while a backup sidecar is live' do
      described_class.pause!(:backup)
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(started_at: Time.current, filename: 'x.tar'),
      )

      described_class.resume_if_idle!

      expect(described_class).to be_paused
    end

    it 'keeps the pause while a PostgreSQL upgrade is pending' do
      described_class.pause!(:postgresql_upgrade)
      Orchestration::PendingOperations.set('postgresql', :upgrade)

      described_class.resume_if_idle!

      expect(described_class).to be_paused
    end

    it 'keeps the pause when the in-flight check itself fails' do
      described_class.pause!(:backup)
      allow(CsvImportRunner).to receive(:in_progress?).and_raise(StandardError, 'docker down')

      described_class.resume_if_idle!

      expect(described_class).to be_paused
    end

    it 'lifts a pause older than MAX_AGE even with an operation in flight' do
      described_class.pause!(:csv_import)
      allow(CsvImportRunner).to receive(:in_progress?).and_return(true)

      travel_to(described_class::MAX_AGE.from_now + 1.minute) do
        described_class.resume_if_idle!
      end

      expect(Orchestration::Runner).to have_received(:unpause)
      expect(described_class).not_to be_paused
    end

    it 'lifts a pause whose marker lost its timestamp' do
      described_class.pause!(:csv_import)
      File.write(marker_path, JSON.generate(reason: 'csv_import'))
      allow(CsvImportRunner).to receive(:in_progress?).and_return(true)

      described_class.resume_if_idle!

      expect(described_class).not_to be_paused
    end

    it 'keeps the marker when unpausing Watchtower fails' do
      described_class.pause!(:backup)
      allow(Orchestration::Runner).to receive(:unpause).and_raise(Orchestration::Runner::CommandError, 'boom')

      expect { described_class.resume_if_idle! }.not_to raise_error
      expect(described_class).to be_paused
    end
  end

  describe '.paused?' do
    it 'is false for an unreadable marker' do
      FileUtils.mkdir_p(File.dirname(marker_path))
      File.write(marker_path, 'not json')

      expect(described_class).not_to be_paused
    end
  end
end
