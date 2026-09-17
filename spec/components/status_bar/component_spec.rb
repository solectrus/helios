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

    # A sensor reads through a source that is not set up, so there is
    # something to start and the source is what holds it back.
    before do
      with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } })
    end

    it 'keeps the button on the bar' do
      expect(rendered.css('.btn-disabled .fa-play')).to be_present
    end

    it 'names what blocks it' do
      expect(rendered.css('.hint .dropdown-content').text).to include(I18n.t('configurations.show.incomplete'))
    end

    it 'paints it in the colour of the warning sign' do
      expect(rendered.css('.hint .dropdown-content').attr('class').value).to include('bg-warning')
    end

    # The bar is broadcast once for clients of either language, so the hint
    # carries both and the stylesheet picks one.
    it 'carries the text in every locale' do
      texts = rendered.css('.dropdown-content .status-bar-label').pluck('data-locale')

      expect(texts).to match_array(I18n.available_locales.map(&:to_s))
    end

    # A disabled button takes neither focus nor tap, so it could not carry the
    # reason to anyone without a pointer. The hint takes the focus instead.
    it 'offers the reason on a focusable trigger' do
      expect(rendered.css('.hint > button[aria-disabled="true"]')).to be_present
    end

    # A screen reader never reaches the bubble: a closed dropdown is hidden.
    it 'repeats the reason where a screen reader finds it' do
      expect(rendered.css('.hint > button .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end

    # In the dropdown the hint takes the place of the button, and the menu
    # styles that place. Without these two the button keeps a quarter of the
    # row while every other entry fills it.
    it 'hands the width of the row on to the button' do
      expect(rendered.css('.hint').attr('class').value).to include('block', 'p-0')
    end
  end

  context 'with a configuration that can start' do
    subject(:rendered) { render_inline(described_class.new(status: :stopped)) }

    before { with_startable_config_yaml }

    it 'offers the button without a hint' do
      expect(rendered.css('button[disabled] .fa-play')).to be_empty
      expect(rendered.css('.hint')).to be_empty
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
