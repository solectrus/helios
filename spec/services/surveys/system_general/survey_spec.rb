RSpec.describe Surveys::SystemGeneral::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    it 'exposes installation_date and timezone in full mode' do
      expect(find_survey_element(result, 'installation_date')).to be_present
      expect(find_survey_element(result, 'timezone')).to be_present
    end

    it 'asks one question per page' do
      expect(section_names(result)).to eq(%w[p_installation p_country p_timezone p_currency])
    end

    # The marker sits on the page, so the whole page goes rather than leaving
    # an empty one behind.
    it 'hides installation_date and country in collectors_only mode (no local PV)' do
      Configuration.current.update('deployment', { 'mode' => 'collectors_only' })

      expect(find_survey_element(result, 'installation_date')).to be_nil
      expect(find_survey_element(result, 'country')).to be_nil
      expect(section_names(result)).to eq(%w[p_timezone p_currency])
      expect(find_survey_element(result, 'timezone')).to include('defaultValue' => 'Europe/Berlin')
    end

    describe 'timezone choices' do
      subject(:choices) { find_survey_element(result, 'timezone')['choices'] }

      it 'stores the IANA identifier and labels it with the standard offset' do
        expect(choices).to include('value' => 'Europe/Berlin', 'text' => '(UTC+01:00) Europe/Berlin')
      end

      it 'sorts by offset' do
        offsets = choices.map { |choice| choice['text'][/\(UTC(.+?)\)/, 1] }

        expect(offsets).to eq(offsets.sort_by { |offset| offset.sub(':', '.').to_f })
      end

      # Rails lists Europe/Zurich twice, as "Bern" and as "Zurich".
      it 'offers every zone once' do
        identifiers = choices.pluck('value')

        expect(identifiers).to eq(identifiers.uniq)
      end

      # A zone of a member state fits that country alone.
      it 'offers every zone of every member state' do
        expect(choices.pluck('value')).to include(*Configuration::COUNTRY_BY_TIMEZONE.keys)
      end

      # A slim tzdata can lack the links among them.
      it 'leaves out a zone the host does not know' do
        allow(ActiveSupport::TimeZone).to receive(:[]).and_call_original
        allow(ActiveSupport::TimeZone).to receive(:[]).with('Europe/Busingen').and_return(nil)

        expect(choices.pluck('value')).not_to include('Europe/Busingen')
      end

      it 'adds a configured zone the curated list does not have' do
        Configuration.current.update('system', { 'timezone' => 'Europe/Oslo' })

        expect(choices).to include('value' => 'Europe/Oslo', 'text' => '(UTC+01:00) Europe/Oslo')
      end
    end

    describe 'country' do
      subject(:codes) { find_survey_element(result, 'country')['choices'].pluck('value') }

      it 'offers the countries the collector has fuel prices for, and one for the rest' do
        expect(codes).to match_array(Configuration::EU_COUNTRIES + ['other'])
        expect(codes.last).to eq('other')
      end

      it 'suggests the country of the timezone' do
        Configuration.current.update('system', { 'timezone' => 'Europe/Vienna' })

        expect(find_survey_element(result, 'country')['defaultValue']).to eq('AT')
      end

      it 'suggests the choice outside the European Union for a timezone there' do
        Configuration.current.update('system', { 'timezone' => 'Europe/Zurich' })

        expect(find_survey_element(result, 'country')['defaultValue']).to eq('other')
      end

      it 'sorts by the name in the language of the page, umlauts included' do
        I18n.with_locale(:de) do
          expect(codes.first(4)).to eq(%w[BE BG DK DE])
          expect(codes.each_cons(3)).to include(%w[NL AT PL])
        end
      end

      it 'sorts by the English name in English' do
        I18n.with_locale(:en) { expect(codes.first(2)).to eq(%w[AT BE]) }
      end
    end

    describe 'suggested timezone' do
      subject(:timezone) { find_survey_element(result, 'timezone') }

      # A new installation answers the country on the page before.
      it 'follows the country while no zone is stored' do
        expect(timezone).not_to have_key('defaultValue')
        expect(timezone['defaultValueExpression']).to include(
          "iif({country} = 'AT', 'Europe/Vienna', ",
          "iif({country} = 'PT', 'Europe/Lisbon', ",
        ).and end_with("'Europe/Berlin'#{')' * Configuration::EU_COUNTRIES.size}")
      end

      it 'keeps a stored zone' do
        Configuration.current.update('system', { 'timezone' => 'Europe/Vienna' })

        expect(timezone).not_to have_key('defaultValueExpression')
      end
    end

    describe 'timezone of the country' do
      # survey-core judges the pairs, as in the browser. Only it knows how it
      # reads `anyof`, `noneof` and the precedence of `or` and `and`. A zone
      # must be one of the choices, or survey-core refuses it anyway.
      def fits(*pairs)
        script = <<~JS
          const { Model } = require('survey-core');
          const { survey, pairs } = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
          const model = new Model(survey);
          const timezone = model.getQuestionByName('timezone');
          console.log(JSON.stringify(pairs.map(([zone, country]) => {
            model.setValue('country', country);
            model.setValue('timezone', zone);
            return !timezone.hasErrors(false);
          })));
        JS
        output, status = Open3.capture2('bun', '-e', script, stdin_data: { survey: result, pairs: }.to_json,
                                                             chdir: Rails.root)
        raise "survey-core failed: #{output}" unless status.success?

        JSON.parse(output)
      end

      it 'accepts the zones of the country' do
        expect(fits(%w[Europe/Berlin DE], %w[Europe/Lisbon PT], %w[Atlantic/Azores PT], %w[Europe/Amsterdam NL]))
          .to all(be(true))
      end

      it 'refuses the zone of another country, even with the same clocks' do
        expect(fits(%w[Europe/Vienna DE], %w[Europe/Athens CY])).to all(be(false))
      end

      # A server often runs on UTC, whatever country it stands in.
      it 'accepts a zone of no member state for every country' do
        expect(fits(%w[Etc/UTC DE], %w[Etc/UTC AT], %w[Europe/London NL], %w[Europe/Zurich DE])).to all(be(true))
      end

      it 'accepts any zone outside the European Union' do
        expect(fits(%w[Europe/Vienna other], %w[America/New_York other])).to all(be(true))
      end

      it 'checks nothing in collectors_only mode, which does not ask for the country' do
        Configuration.current.update('deployment', { 'mode' => 'collectors_only' })

        expect(find_survey_element(result, 'timezone')['validators']).to be_nil
      end
    end

    describe 'currency' do
      it 'offers the preset dropdown and a single free-text field' do
        expect(find_survey_element(result, 'currency_preset')).to include('type' => 'dropdown')
        currency = find_survey_element(result, 'currency')
        expect(currency).to include('type' => 'text', 'visibleIf' => "{currency_preset} = 'other'")
      end

      it 'announces itself in the header' do
        expect(result['description']['default']).to include('currency')
      end
    end
  end
end
