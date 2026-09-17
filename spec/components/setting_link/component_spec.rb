RSpec.describe SettingLink::Component, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(setting: 'system_general', configuration: Configuration.current))
  end

  before { with_config_yaml }

  it 'names the setting' do
    expect(rendered.text).to include(I18n.t('configurations.settings.system_general.title'))
  end

  # Nothing on the Settings page can be open, so the chip has no state to
  # report and carries the label alone (see CommissioningController).
  it 'carries no state icon' do
    expect(rendered.css('i.fa-triangle-exclamation')).to be_empty
    expect(rendered.css('i.fa-check')).to be_empty
    expect(rendered.css('.sr-only')).to be_empty
  end

  it 'opens the form of a setting that already carries a value' do
    expect(rendered.css('a').attr('href').value).to eq(
      '/configuration/system_general/system_general/edit',
    )
  end

  it 'opens the empty form of a setting nothing has been saved for' do
    rendered = render_inline(described_class.new(setting: 'tibber', configuration: Configuration.current))

    expect(rendered.css('a').attr('href').value).to eq('/configuration/settings/new?setting=tibber')
  end
end
