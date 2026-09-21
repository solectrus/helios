RSpec.describe Surveys::ReverseProxy::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    # One field, one question, whatever the mode: the address the stack answers
    # on. The hints around it say which of the three it is.
    it 'asks for the address once' do
      names = Array(result['pages']).flat_map { |page| page['elements'].pluck('name') }

      expect(names.count('app_host')).to eq(1)
    end

    # The mode stands on a page of its own. Every field below it appears or
    # disappears with the answer, and on one page with the radios each of them
    # moved the next radio out from under the cursor.
    it 'keeps the mode on a page of its own' do
      mode, address, proxy = Array(result['pages'])

      expect(mode['elements'].pluck('name')).to eq(%w[mode])
      expect(address['elements'].pluck('name')).to include('app_host')
      expect(proxy['elements'].pluck('name'))
        .to include('letsencrypt_email', 'force_ssl', 'trusted_proxy_ranges')
    end

    # The managed Traefik routes HELIOS itself, so choosing it moves the screen
    # the user is standing on to the domain they type. A domain that does not
    # point here yet takes HELIOS with it, and only a hand-edited compose.yaml
    # brings it back. The hint carries the port HELIOS answers on there, so it
    # has to stay the port the export binds.
    it 'warns that HELIOS follows the domain, on the port it is bound to' do
      hint = Array(result['pages'])
             .flat_map { |page| page['elements'] }
             .find { |element| element['name'] == 'address_hint_internal' }

      expect(hint['html']['de']).to include(Export::Services::Helios::HOST_PORT.to_s)
      expect(hint['html']['default']).to include(Export::Services::Helios::HOST_PORT.to_s)
    end

    # FORCE_SSL makes the dashboard redirect HTTP to HTTPS, which rules out the
    # direct access over a host port that the "none" mode describes. The
    # managed Traefik implies the flag, so one mode is left to ask in.
    it 'asks for the TLS marker behind an external proxy alone' do
      expect(find_survey_element(result, 'force_ssl')['visibleIf']).to eq("{mode} = 'external'")
    end

    # Direct access works without an address, because every caller falls back
    # to the published port. A proxy routes by host rule and cannot.
    it 'demands an answer for either proxy mode alone' do
      expect(find_survey_element(result, 'app_host')['requiredIf']).to eq("{mode} <> 'none'")
    end

    it 'refuses an address that names the machine to itself' do
      validator = find_survey_element(result, 'app_host')['validators'].first

      expect(validator).to include('type' => 'regex', 'caseInsensitive' => true)
      expect(validator['regex']).to eq(HostAddress::SURVEY_PATTERN)
    end

    # Without a proxy the address bar holds the address of this machine, which
    # is what the field takes. Behind either proxy the field takes a domain and
    # the bar names it nowhere, and the field is mandatory there, so an offer
    # would settle the requirement with the one value it must not hold.
    #
    # This form asks for the mode in the same run, so the offer names the answer
    # it holds under. Reading the stored mode here would say nothing about the
    # one the user is about to choose.
    it 'lets the browser offer the address while no proxy is chosen' do
      expect(result['offerBrowserHost']).to eq(
        'question' => 'app_host',
        'while' => { 'question' => 'mode', 'values' => ['none'] },
      )
    end

    %w[internal external].each do |mode|
      it "carries the same offer with #{mode} mode stored" do
        with_config_yaml('reverse_proxy' => { 'mode' => mode })

        expect(result.dig('offerBrowserHost', 'while', 'values')).to eq(['none'])
      end
    end

    # The condition points at questions and answers of this very form. Renaming
    # either one without the offer would leave a rule that never holds, and the
    # address field would stay empty where the browser answers it.
    it 'names a question and a mode the form offers' do
      offer = result['offerBrowserHost']
      choices = find_survey_element(result, offer.dig('while', 'question'))['choices'].pluck('value')

      expect(choices).to include(*offer.dig('while', 'values'))
      expect(find_survey_element(result, offer['question'])).to be_present
    end
  end

  # What a mode owns is written down twice: here as the rule that shows a
  # field, and in SettingPersistence::REVERSE_PROXY_MODE_FIELDS as the rule
  # that stores it. A field shown in one place and dropped in the other keeps
  # a value nobody can see, or loses one the form still asks for, so the two
  # lists are held to each other rather than kept in step by hand.
  describe 'the fields of each mode' do
    subject(:survey) { described_class.new.call }

    before { with_config_yaml }

    # The answers the form stores: the html blocks around them explain, they
    # carry no value. `mode` itself names the mode rather than being one of its
    # fields, so the table carries it separately.
    def visible_fields(mode)
      Array(survey['pages'])
        .flat_map { |page| Array(page['elements']) }
        .reject { |element| element['type'] == 'html' || element['name'] == 'mode' }
        .select { |element| visible_in?(element, mode) }
        .pluck('name')
    end

    # The two shapes the form uses, both of them about the mode alone.
    def visible_in?(element, mode)
      case element['visibleIf']
      when nil then true
      when /\A\{mode\} = '(\w+)'\z/ then Regexp.last_match(1) == mode
      when /\A\{mode\} <> '(\w+)'\z/ then Regexp.last_match(1) != mode
      else raise "Unknown rule #{element['visibleIf'].inspect} on #{element['name']}"
      end
    end

    SettingPersistence::REVERSE_PROXY_MODE_FIELDS.each do |mode, fields|
      it "stores every field the #{mode} mode shows, and nothing else" do
        expect(fields - %w[mode]).to match_array(visible_fields(mode))
      end
    end

    # Every mode the radio offers has a row in the table, and every row an
    # answer on the radio.
    it 'covers every mode the form offers' do
      choices = find_survey_element(survey, 'mode')['choices'].pluck('value')

      expect(SettingPersistence::REVERSE_PROXY_MODE_FIELDS.keys).to match_array(choices)
    end
  end
end
