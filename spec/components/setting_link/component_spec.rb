RSpec.describe SettingLink::Component, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(setting: 'system_general', configuration: Configuration.current, **options))
  end

  before { with_config_yaml }

  describe 'a chip in the required tier' do
    let(:options) { { required: true } }

    # The commissioning date is the one value a fresh installation has to
    # supply, so the chip says whether it is already there.
    it 'warns while the setting is still empty' do
      expect(rendered.css('i.fa-triangle-exclamation')).to be_present
      expect(rendered.css('i.fa-check')).to be_empty
    end

    it 'confirms once the setting carries a value' do
      Configuration.current.update('system_general', { 'installation_date' => '2024-03-01' })

      expect(rendered.css('i.fa-check')).to be_present
      expect(rendered.css('i.fa-triangle-exclamation')).to be_empty
    end

    it 'names the state for a reader that cannot see the icon' do
      expect(rendered.css('.sr-only').text).to be_present
    end
  end

  # An optional setting ships with a workable value, so it has no state worth
  # reporting and the chip stays plain.
  describe 'a chip in the optional tier' do
    let(:options) { {} }

    it 'carries no state icon' do
      expect(rendered.css('i.fa-check')).to be_empty
      expect(rendered.css('i.fa-triangle-exclamation')).to be_empty
    end
  end
end
