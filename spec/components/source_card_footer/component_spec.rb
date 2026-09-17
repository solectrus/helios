RSpec.describe SourceCardFooter::Component, type: :component do
  # A card with a switch dims its footer before the server answers, which the
  # Stimulus controller does through these targets. Without them the footer
  # stays bright until the page comes back (see
  # SettingSection::Component#stimulus_scope).
  it 'hands the switch of a card the targets it dims through' do
    component = described_class.new(sensor_count: 2, stimulus_scope: 'setting-section--component')

    expect(component.wrapper_data).to eq('setting-section--component-target' => 'dim')
    expect(component.link_data).to eq(
      turbo_frame: '_top',
      'setting-section--component-target' => 'link',
    )
  end

  # The external input has no switch, so it has no controller to report to.
  it 'leaves the targets off a card without a switch' do
    component = described_class.new(sensor_count: 0)

    expect(component.wrapper_data).to eq({})
    expect(component.link_data).to eq(turbo_frame: '_top')
    expect(component.dimmed?).to be(false)
  end
end
