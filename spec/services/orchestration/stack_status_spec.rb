RSpec.describe Orchestration::StackStatus do
  before do
    described_class.instance.reset!
    Orchestration::PendingOperations.clear_all
  end

  describe '#overall' do
    context 'when not initialized' do
      before do
        # Stub refresh! to avoid real Docker calls, just mark as initialized
        allow(described_class.instance).to receive(:refresh!) do
          described_class
            .instance
            .instance_variable_get(:@initialized)
            .make_true
        end
      end

      it 'triggers refresh on first call' do
        described_class.overall
        expect(described_class.instance).to have_received(:refresh!)
      end
    end

    context 'when initialized with no services' do
      before do
        described_class.instance.instance_variable_get(:@initialized).make_true
      end

      it 'returns :stopped' do
        expect(described_class.overall).to eq(:stopped)
      end
    end
  end

  describe '#update and compute_overall' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
      allow(Orchestration::AffectedServices).to receive(:compute).and_return([])
    end

    it 'returns :ok when all services are running' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :running)

      expect(described_class.overall).to eq(:ok)
    end

    it 'returns :stopped when all services are stopped' do
      described_class.update('postgresql', :stopped)
      described_class.update('redis', :stopped)

      expect(described_class.overall).to eq(:stopped)
    end

    it 'returns :error when any service has error' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :error)

      expect(described_class.overall).to eq(:error)
    end

    it 'returns :starting when any service is starting' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :starting)

      expect(described_class.overall).to eq(:starting)
    end

    it 'returns :partial when some services are stopped' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :stopped)

      expect(described_class.overall).to eq(:partial)
    end

    it 'returns :restart_required when affected services exist' do
      allow(Orchestration::AffectedServices).to receive(:compute).and_return(
        %w[redis],
      )
      described_class.update('postgresql', :running)
      described_class.update('redis', :running)

      expect(described_class.overall).to eq(:restart_required)
    end
  end

  describe '#service_counts' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
    end

    it 'returns zero counts when no services exist' do
      expect(described_class.service_counts).to eq(running: 0, total: 0)
    end

    it 'counts running services correctly' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :stopped)
      described_class.update('influxdb', :running)

      expect(described_class.service_counts).to eq(running: 2, total: 3)
    end

    it 'counts all non-stopped services as running' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :error)
      described_class.update('influxdb', :starting)
      described_class.update('mqtt', :stopped)

      expect(described_class.service_counts).to eq(running: 3, total: 4)
    end
  end

  # Watchtower is down for as long as a backup, import, restore or upgrade
  # runs (see UpdatePause). Counting it would report the stack as partially
  # down for the duration, every single night.
  describe '#refresh! (Watchtower while updates are paused)' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [], invalidate_config_hashes: nil,
      )
      allow(Compose).to receive(:load).and_return(
        instance_double(
          Compose::File,
          services: [
            instance_double(Compose::Service, name: 'postgresql', helios?: false),
            instance_double(Compose::Service, name: 'watchtower', helios?: false),
          ],
        ),
      )
      allow(Orchestration::Container).to receive_messages(
        invalidate_cache: nil,
        all: [instance_double(Orchestration::Container, service_name: 'postgresql', effective_status: :ok)],
      )
    end

    it 'leaves it out of the stack status entirely' do
      allow(Orchestration::UpdatePause).to receive(:paused?).and_return(true)

      described_class.refresh!

      aggregate_failures do
        expect(described_class.status_for('watchtower')).to be_nil
        expect(described_class.service_counts).to eq(running: 1, total: 1)
        expect(described_class.overall).to eq(:ok)
      end
    end

    it 'counts it like any other service otherwise' do
      allow(Orchestration::UpdatePause).to receive(:paused?).and_return(false)

      described_class.refresh!

      aggregate_failures do
        expect(described_class.status_for('watchtower')).to eq(:stopped)
        expect(described_class.service_counts).to eq(running: 1, total: 2)
        expect(described_class.overall).to eq(:partial)
      end
    end
  end

  describe '#mark_starting!' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
      allow(Orchestration::AffectedServices).to receive(:compute).and_return([])
    end

    it 'returns :starting when flag is set and some services are stopped' do
      described_class.update('postgresql', :ok)
      described_class.update('redis', :stopped)
      described_class.mark_starting!

      expect(described_class.overall).to eq(:starting)
    end

    it 'keeps :starting until services finish settling' do
      described_class.update('postgresql', :ok)
      described_class.update('redis', :starting)
      described_class.mark_starting!

      # Service finishes starting — but flag keeps overall as :starting
      # until services_settling? returns false
      described_class.update('redis', :ok)

      expect(described_class.overall).to eq(:ok)
    end

    it 'clears starting flag when no services are settling' do
      described_class.mark_starting!
      described_class.update('postgresql', :ok)
      described_class.update('redis', :stopped)

      # No service is :starting, so the flag gets cleared
      expect(described_class.overall).to eq(:partial)
    end

    it 'keeps starting flag while another start-like op is still pending' do
      described_class.mark_starting!
      Orchestration::PendingOperations.set('redis', :start)
      described_class.update('postgresql', :ok)
      described_class.update('redis', :stopped)

      # PostgreSQL finished, but Redis still has a queued start —
      # bar must not flicker to :partial in the gap.
      expect(described_class.overall).to eq(:starting)
    end
  end

  describe '#mark_stopping!' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
    end

    it 'returns :stopping when flag is set and services are running' do
      described_class.update('postgresql', :ok)
      described_class.update('redis', :ok)
      described_class.mark_stopping!

      expect(described_class.overall).to eq(:stopping)
    end

    it 'returns :stopping even when some services are already stopped' do
      described_class.update('postgresql', :ok)
      described_class.update('redis', :stopped)
      described_class.mark_stopping!

      expect(described_class.overall).to eq(:stopping)
    end

    it 'clears stopping flag when all services are stopped' do
      described_class.mark_stopping!
      described_class.update('postgresql', :stopped)
      described_class.update('redis', :stopped)

      expect(described_class.overall).to eq(:stopped)
    end
  end

  describe '#mark_config_changed!' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
      allow(described_class.instance).to receive(:rebuild_stack)
    end

    # The services the rewritten compose contains afterwards.
    def stub_compose_with(*names)
      allow(Compose).to receive(:load).and_return(
        instance_double(
          Compose::File,
          services: names.map { |name| instance_double(Compose::Service, name:, helios?: false) },
        ),
      )
    end

    it 'rebuilds stack files' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [],
        invalidate_config_hashes: nil,
      )
      described_class.mark_config_changed!

      expect(described_class.instance).to have_received(:rebuild_stack)
    end

    it 'invalidates config hashes and affected services cache' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [],
        invalidate_config_hashes: nil,
      )
      described_class.mark_config_changed!

      expect(Orchestration::AffectedServices).to have_received(
        :invalidate_config_hashes,
      )
    end

    it 'sets restart_required when services are affected' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: %w[redis],
        invalidate_config_hashes: nil,
      )
      stub_compose_with('redis')
      described_class.update('redis', :running)
      described_class.mark_config_changed!

      expect(described_class.overall).to eq(:restart_required)
    end

    # A service switched off in the settings vanishes from the rewritten
    # compose. Its stale entry used to survive in the status map and keep the
    # bar amber with "9 of 10 services running" while no tenth service existed.
    it 'drops services the rewritten compose no longer has' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [],
        invalidate_config_hashes: nil,
      )
      stub_compose_with('postgresql')
      described_class.update('postgresql', :ok)
      described_class.update('tibber', :stopped)

      described_class.mark_config_changed!

      aggregate_failures do
        expect(described_class.status_for('tibber')).to be_nil
        expect(described_class.service_counts).to eq(running: 1, total: 1)
        expect(described_class.overall).to eq(:ok)
      end
    end

    it 'picks up services the rewritten compose has gained' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [],
        invalidate_config_hashes: nil,
      )
      stub_compose_with('postgresql', 'tibber')
      allow(Orchestration::Container).to receive(:find).with('tibber').and_return(nil)
      described_class.update('postgresql', :ok)

      described_class.mark_config_changed!

      aggregate_failures do
        expect(described_class.status_for('tibber')).to eq(:stopped)
        expect(described_class.service_counts).to eq(running: 1, total: 2)
        expect(described_class.overall).to eq(:partial)
      end
    end

    it 'keeps the running status of a service whose container is still up' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: [],
        invalidate_config_hashes: nil,
      )
      stub_compose_with('tibber')
      allow(Orchestration::Container).to receive(:find).with('tibber').and_return(
        instance_double(Orchestration::Container, effective_status: :ok),
      )

      described_class.mark_config_changed!

      expect(described_class.service_counts).to eq(running: 1, total: 1)
    end

    it 'returns affected service names' do
      allow(Orchestration::AffectedServices).to receive_messages(
        compute: %w[redis influxdb],
        invalidate_config_hashes: nil,
      )
      described_class.mark_config_changed!

      expect(described_class.pending_restart_services).to eq(%w[redis influxdb])
    end
  end

  describe '#pending_restart_services' do
    it 'delegates to AffectedServices.compute' do
      allow(Orchestration::AffectedServices).to receive(:compute).and_return(
        %w[redis],
      )

      expect(described_class.pending_restart_services).to eq(%w[redis])
    end
  end

  describe '#services_settling?' do
    before do
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
    end

    it 'returns true when a service is starting' do
      described_class.update('postgresql', :starting)

      expect(described_class.services_settling?).to be true
    end

    it 'returns false when all services are running' do
      described_class.update('postgresql', :running)

      expect(described_class.services_settling?).to be false
    end
  end

  describe '#reset!' do
    before do
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(
        instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil),
      )
      described_class.update('postgresql', :running)
    end

    it 'clears all state' do
      described_class.reset!

      initialized =
        described_class.instance.instance_variable_get(:@initialized)
      expect(initialized.true?).to be false
    end

    it 'invalidates config hashes and affected services cache' do
      allow(Orchestration::AffectedServices).to receive(:invalidate_config_hashes)
      described_class.reset!

      expect(Orchestration::AffectedServices).to have_received(
        :invalidate_config_hashes,
      )
    end
  end
end
