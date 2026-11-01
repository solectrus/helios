module Surveys
  module SystemGeneral
    class Survey < Base
      private

      def customize!(data)
        timezone = find_element(data, 'timezone')
        return unless timezone

        timezone['choices'] = timezone_choices

        country = find_element(data, 'country')
        return unless country

        country['choices'] = country_choices(country['choices'])
        country['defaultValue'] = configuration.country || Configuration::OTHER_COUNTRY
        timezone['validators'] = [country_validator]
        follow_country!(timezone) if configuration.system.timezone.blank?
      end

      # Without a stored zone, the suggestion follows the country asked for on
      # the page before: Austria suggests Europe/Vienna. The fixed default
      # stays for a country outside the European Union.
      def follow_country!(timezone)
        fallback = "'#{timezone.delete('defaultValue')}'"
        timezone['defaultValueExpression'] =
          Configuration::TIMEZONES_BY_COUNTRY.reduce(fallback) do |rest, (code, zones)|
            "iif({country} = '#{code}', '#{zones.first}', #{rest})"
          end
      end

      # A timezone of a member state fits that country alone. Europe/Vienna
      # does not pass for Germany, Europe/Berlin does. Any other zone (UTC,
      # CET, Europe/Zurich) names no member state and fits every country.
      def country_validator
        matches = Configuration::TIMEZONES_BY_COUNTRY.map do |code, zones|
          "({country} = '#{code}' and {timezone} anyof #{expression_list(zones)})"
        end
        unbound = "{timezone} noneof #{expression_list(Configuration::COUNTRY_BY_TIMEZONE.keys)}"

        {
          'type' => 'expression',
          'expression' => ["{country} = '#{Configuration::OTHER_COUNTRY}'", unbound, *matches].join(' or '),
          'text' => self.class.localized(
            en: 'This timezone does not match the selected country.',
            de: 'Diese Zeitzone passt nicht zum gewählten Land.',
          ),
        }
      end

      def expression_list(values)
        "[#{values.map { |value| "'#{value}'" }.join(', ')}]"
      end

      # The member states, named in both languages, and the choice outside the
      # European Union from the survey file.
      def country_choices(others)
        members = Configuration::EU_COUNTRIES.map do |code|
          { 'value' => code, 'text' => self.class.localized(en: country_name(code, :en), de: country_name(code, :de)) }
        end
        sort_by_name(members + others)
      end

      def country_name(code, locale)
        I18n.t!(code, scope: :countries, locale:)
      end

      # SurveyJS sorts by code point, which puts "Österreich" after "Zypern".
      # Transliterating first sorts the umlauts where a reader expects them.
      # The choice outside the European Union stays last.
      def sort_by_name(choices)
        key = I18n.locale == :de ? 'de' : 'default'

        choices.sort_by do |choice|
          [choice['value'] == Configuration::OTHER_COUNTRY ? 1 : 0, I18n.transliterate(choice['text'][key])]
        end
      end

      # Rails curates the tz database down to the zones people actually pick.
      # That list stays short enough to scroll through, unlike the 500-odd raw
      # identifiers, and the offset in front of each one groups them the way
      # somebody looking for their own zone expects. It is the zone's standard
      # offset, so the labels stay put when daylight saving time starts.
      def timezone_choices
        curated_zones.map do |zone|
          identifier = zone.tzinfo.name

          { 'value' => identifier, 'text' => "(UTC#{zone.formatted_offset}) #{identifier}" }
        end
      end

      # Rails lists some zones twice, under two city names ("Bern" and
      # "Zurich" are both Europe/Zurich), which would put the same value in
      # the field twice. Sorting by identifier rather than by those city names
      # also keeps each offset's entries in the order they are labelled in.
      # Every zone of a member state joins in, because the validator accepts
      # only the own zones for such a country, and Rails has none for Cyprus or
      # Malta. A zone the tz files of the host do not know stays out.
      def curated_zones
        zones = ActiveSupport::TimeZone.all +
                Configuration::COUNTRY_BY_TIMEZONE.keys.filter_map { |id| ActiveSupport::TimeZone[id] }
        zones += [current_zone] if current_zone

        zones.uniq { |zone| zone.tzinfo.name }.sort_by { |zone| [zone.utc_offset, zone.tzinfo.name] }
      end

      # A configuration imported from an existing installation can carry a
      # zone outside the curated set, and the field must still show it.
      def current_zone
        identifier = configuration.system.timezone.presence
        return unless identifier
        return if ActiveSupport::TimeZone.all.any? { |zone| zone.tzinfo.name == identifier }

        ActiveSupport::TimeZone[identifier]
      end
    end
  end
end
