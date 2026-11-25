RSpec.describe ServiceRow::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(compose_service:, container:, lazy: false)) }

  let(:service_name) { 'dashboard' }
  let(:compose_service) { Compose::Service.new(service_name, 'image' => image) }
  let(:container) { build_container(state: 'running', health: 'healthy') }
  let(:image) { 'ghcr.io/solectrus/solectrus:latest' }

  before do
    Orchestration::PendingOperations.clear_all
    allow(Orchestration::AffectedServices).to receive(:compute).and_return([])
  end

  after { Orchestration::PendingOperations.clear_all }

  def build_container(state:, health:)
    orchestration_container(service: service_name, state:, health:, image:)
  end

  it 'marks a healthy container green' do
    expect(rendered.css('.bg-success')).to be_present
  end

  # Docker states HELIOS has no dedicated color for (dead, restarting) are an
  # error, not a neutral "not running".
  context 'with a container in an unexpected state' do
    let(:container) { build_container(state: 'dead', health: nil) }

    it 'marks it as an error' do
      expect(rendered.css('.bg-error')).to be_present
    end
  end

  # HELIOS manages itself last and sits visually apart from the stack it runs.
  context 'with the HELIOS row itself' do
    let(:service_name) { 'helios' }
    let(:image) { 'ghcr.io/solectrus/helios:latest' }

    it 'renders on its own background' do
      expect(rendered.to_html).to include('bg-base-300/60')
    end
  end

  # A foreign broker of the same name keeps its compose entry verbatim, so the
  # image upgrade would write into a section the export never renders and the
  # hint would come back on every render.
  context 'with an unmanaged service carrying a known legacy image' do
    let(:service_name) { 'mosquitto' }
    let(:image) { 'eclipse-mosquitto:2' }

    before do
      with_config_yaml('_unmanaged' => { 'services' => { 'mosquitto' => { 'image' => image } } })
    end

    it 'offers no image upgrade' do
      expect(rendered.to_html).not_to include('Upgrade recommended')
    end
  end

  context 'with a managed service carrying a known legacy image' do
    let(:service_name) { 'mosquitto' }
    let(:image) { 'eclipse-mosquitto:2' }

    it 'offers the image upgrade' do
      expect(rendered.to_html).to include('Upgrade recommended')
    end
  end

  # The update button does the same thing either way, but the reason tells the
  # user whether the image moved or only the configuration did.
  context 'when only the configuration changed' do
    before { allow(Orchestration::AffectedServices).to receive(:compute).and_return([service_name]) }

    it 'explains the pending recreate as a configuration change' do
      expect(rendered.to_html).to include('Configuration changed')
    end
  end

  describe 'the reason of a pending restart' do
    subject(:recreate) { rendered.css('[id$="-recreate"]') }

    before do
      with_config_yaml
      allow(Orchestration::AffectedServices).to receive(:compute).and_return([service_name])
    end

    def stub_change(**attrs)
      change = Orchestration::ConfigFingerprints::Change.new(
        added: [], removed: [], changed: [], parts: [], **attrs,
      )
      allow(Orchestration::AffectedServices).to receive(:change_for).with(service_name).and_return(change)
    end

    it 'lists what the restart applies below the reason' do
      stub_change(added: ['INFLUX_SENSOR_GRID_EXPORT_POWER'])

      expect(recreate.css('.tooltip-content p').text).to eq('Restart required for these changes:')
      expect(recreate.css('.tooltip-content li').map(&:text)).to eq(
        ["New sensor: #{I18n.t('sensors.grid_export_power')}"],
      )
    end

    # daisyUI would draw a second bubble from data-tip.
    it 'drops the one-line tooltip while the list shows' do
      stub_change(added: ['INFLUX_SENSOR_GRID_EXPORT_POWER'])

      expect(recreate.attr('data-tip')).to be_nil
      expect(recreate.css('button').attr('aria-label').value).to eq('Configuration changed, restart required')
    end

    it 'keeps the one-line tooltip when nothing can be named' do
      allow(Orchestration::AffectedServices).to receive(:change_for).and_return(nil)

      expect(recreate.attr('data-tip').value).to eq('Configuration changed, restart required')
      expect(recreate.css('.tooltip-content')).to be_empty
    end
  end

  # An incomplete configuration blocks every start, and it belongs to the
  # installation rather than to one service, so no row marks it. The start
  # button it refuses is where the row can still say it.
  describe 'the start button' do
    subject(:tooltip) { rendered.css('[id$="-start"]') }

    context 'with an incomplete configuration and a stopped service' do
      # The row carries a second hint on its status dot, so scope to the
      # button group.
      subject(:hint) { rendered.css('.join .hint') }

      let(:container) { build_container(state: 'exited', health: nil) }

      before { with_config_yaml }

      # The same wording and the same colour the warning sign in the
      # navigation carries.
      it 'names the reason it refuses' do
        expect(hint.css('.dropdown-content').text.strip).to eq(I18n.t('configurations.show.incomplete'))
      end

      it 'marks it as a warning' do
        expect(hint.css('.dropdown-content').attr('class').value).to include('bg-warning')
      end

      # A disabled button takes neither focus nor tap, so the reason would
      # reach nobody without a pointer. A span that only looks disabled lets
      # the hint own the focus.
      it 'keeps the reason on a focusable trigger' do
        expect(hint.css('button[aria-disabled="true"] .fa-play')).to be_present
        expect(rendered.css('[id$="-start"][disabled]')).to be_empty
      end

      # A closed dropdown is hidden, so a screen reader never reaches the
      # bubble. The trigger repeats the words.
      it 'repeats the reason where a screen reader finds it' do
        expect(hint.css('button .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
      end
    end

    # The installation-wide warning belongs on the button only while nothing
    # nearer blocks the start. A running service is blocked by its own state,
    # which the row shows anyway, and the navigation and the status bar carry
    # the warning at the same time.
    context 'with an incomplete configuration and a running service' do
      before { with_config_yaml }

      it 'names the action' do
        expect(tooltip.attr('data-tip').value).to eq('Start')
      end

      it 'leaves the tooltip as it is' do
        expect(tooltip.attr('class').value).to include('tooltip-info')
      end
    end

    context 'with a configuration that can start' do
      before { with_startable_config_yaml }

      # Nothing refuses here, so the label is a plain hover tooltip again, and
      # the button carries the name a screen reader reads.
      it 'names the action' do
        expect(tooltip.attr('data-tip').value).to eq('Start')
        expect(tooltip.css('button').attr('aria-label').value).to eq('Start')
      end

      it 'leaves the tooltip as it is' do
        expect(tooltip.attr('class').value).to include('tooltip-info')
      end
    end
  end
end
