RSpec.describe StatusBar::Component, type: :component do
  before do
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(Orchestration::StackStatus).to receive(:service_counts).and_return(running: 2, total: 3)
  end

  # The bar names the services a restart would cover, so the user can tell
  # whether the pending change touches what they just edited.
  it 'lists the services waiting for a restart' do
    allow(Orchestration::StackStatus).to receive(:pending_restart_services).and_return(%w[dashboard influxdb])

    rendered = render_inline(described_class.new(status: :restart_required))

    expect(rendered.to_html).to include('Dashboard, InfluxDB')
  end

  it 'falls back to the plain status text when nothing is pending' do
    allow(Orchestration::StackStatus).to receive(:pending_restart_services).and_return([])

    rendered = render_inline(described_class.new(status: :restart_required))

    expect(rendered.to_html).not_to include('Dashboard, InfluxDB')
  end

  # An incomplete configuration blocks the start. The bar keeps the button
  # rather than dropping it, because the empty place would say nothing about
  # why (the service rows behave the same way).
  describe 'the start action with an incomplete configuration' do
    subject(:rendered) { render_inline(described_class.new(status: :stopped)) }

    # A sensor reads through a complete source, so there is something to
    # start. Only the commissioning date is still missing.
    before do
      with_config_yaml(
        'senec' => { 'version' => '4' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )
    end

    it 'keeps the button on the bar' do
      expect(rendered.css('button[disabled] .fa-play')).to be_present
    end

    it 'names what blocks it, in the colour of the warning sign' do
      tooltip = rendered.css('.tooltip-warning .tooltip-content')

      expect(tooltip.text).to include(I18n.t('configurations.show.incomplete'))
    end

    # The bar is broadcast once for clients of either language, so the
    # tooltip carries both and the stylesheet picks one.
    it 'carries the text in every locale' do
      texts = rendered.css('.tooltip-content .status-bar-label').pluck('data-locale')

      expect(texts).to match_array(I18n.available_locales.map(&:to_s))
    end

    # A touch device has no hover, so the stylesheet opens a tooltip there on
    # focus alone. The disabled button takes no focus, so the wrapper has to.
    it 'can take the focus a tap gives it' do
      expect(rendered.css('.tooltip-warning').attr('tabindex').value).to eq('-1')
    end

    # In the dropdown the wrapper takes the place of the button, and the menu
    # styles that place. Without these two the button keeps a quarter of the
    # row while every other entry fills it.
    it 'hands the width of the row on to the button' do
      classes = rendered.css('.tooltip-warning').attr('class').value

      expect(classes).to include('block', 'p-0')
    end
  end

  context 'with a configuration that can start' do
    subject(:rendered) { render_inline(described_class.new(status: :stopped)) }

    before { with_startable_config_yaml }

    it 'offers the button without a tooltip' do
      expect(rendered.css('button[disabled] .fa-play')).to be_empty
      expect(rendered.css('.tooltip-warning')).to be_empty
    end
  end

  # Before the first sensor there is nothing to start at all. The screen
  # behind the bar says so on its own, so a refusing button adds nothing.
  context 'without a single sensor' do
    subject(:rendered) { render_inline(described_class.new(status: :stopped)) }

    before { with_config_yaml }

    it 'leaves the start action off the bar' do
      expect(rendered.css('.fa-play')).to be_empty
    end
  end
end
