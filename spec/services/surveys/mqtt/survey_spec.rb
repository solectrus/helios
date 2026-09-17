RSpec.describe Surveys::Mqtt::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'no longer carries an image page (channel choice lives in the software survey)' do
      expect(section_names(result)).not_to include('p_image')
    end

    # Clearing the username drops the password on save (drop_half_credentials!),
    # so the password must leave the survey at the same moment. Otherwise the
    # field keeps a password that is discarded on save, and the broker turns
    # open while the form still shows a login.
    it 'clears the password as soon as the username goes' do
      expect(find_survey_element(result, 'password')).to include(
        'visibleIf' => '{username} notempty',
        'clearIfInvisible' => 'onHidden',
      )
    end

    # Two services on one host port stop the stack. The broker keeps its own
    # port out of the list, or the form would refuse the value it already
    # carries and the section could never be saved again.
    it 'keeps the broker off the ports of the other services' do
      with_config_yaml(
        'mosquitto' => { 'port' => '1884' },
        'dashboard' => { 'host_port' => '3001' },
        'influxdb' => { 'host_port' => '8087' },
      )

      expect(find_survey_element(result, 'port')['validators'].pluck('expression')).to eq(
        ['{port} <> 80 and {port} <> 443 and {port} <> 3001 and {port} <> 3999 and ' \
         '{port} <> 4567 and {port} <> 8087 and {port} <> 8883'],
      )
    end

    describe 'the kind of broker the form opens on' do
      # broker_external is never stored, so only the default preselects it.
      it 'offers a broker of the user while no flag is set' do
        expect(find_survey_element(result, 'broker_external')['defaultValue']).to be(true)
      end

      it 'offers the managed broker once HELIOS runs one' do
        with_config_yaml('mqtt' => { 'broker_managed' => true })

        expect(find_survey_element(result, 'broker_external')['defaultValue']).to be(false)
      end
    end
  end
end
