RSpec.describe Surveys::Deployment::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    it 'asks for the mode first' do
      expect(section_names(result).first).to eq('p_mode')
    end

    # Choosing collectors_only means the collectors write to an InfluxDB
    # elsewhere, and HELIOS has no address to fall back on. Asking here is what
    # keeps the answer from being missing afterwards.
    it 'carries the external database along with the mode' do
      expect(section_names(result)).to eq(%w[p_mode p_connection p_credentials])
    end

    it 'shows the external database only for the mode that needs one' do
      pages = result['pages'].reject { |page| page['name'] == 'p_mode' }

      expect(pages.pluck('visibleIf')).to all(eq("{mode} = 'collectors_only'"))
    end

    # The condition reads the answer given in this survey, so the pages must
    # not also be gated by the mode that is stored today.
    it 'keeps the pages whatever mode is stored' do
      Configuration.current.update('deployment', { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      expect(section_names(result)).to eq(%w[p_mode p_connection p_credentials])
    end

    it 'requires the address of the external database' do
      expect(find_survey_element(result, 'host')).to include('isRequired' => true)
    end

    it 'requires the credentials it writes with' do
      expect(find_survey_element(result, 'token_write')).to include('isRequired' => true)
    end
  end
end
