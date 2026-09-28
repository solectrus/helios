module Surveys
  module Sensor
    # The total generation of SENEC can be read by the total sensor or by a PV
    # string (see SensorMappings::SENEC_TOTAL_CAPABLE_SENSORS), but only by one
    # sensor at a time (see Configuration#senec_total_reader).
    #
    # A PV string gets the choice between its own string and the total. The
    # gate sits on the question rather than the page, so switching to another
    # source clears the answer (see clearInvisibleValues). While another
    # sensor reads the total, a validator refuses it here in the form, on the
    # PV string and on the total sensor alike.
    class SenecTotalInjector
      def initialize(sensor_name)
        @sensor_name = sensor_name
      end

      def call(survey)
        capable = SensorMappings::SENEC_TOTAL_CAPABLE_SENSORS.include?(sensor_name)
        return unless capable || sensor_name == 'inverter_power'

        reader = Configuration.current.senec_total_reader(except: sensor_name)
        if capable
          inject_field_page!(survey, reader)
        elsif reader
          refuse!(Base.find_element(survey, 'source'), "{source} <> 'senec'", reader)
        end
      end

      private

      attr_reader :sensor_name

      def inject_field_page!(survey, reader)
        element = field_element
        refuse!(element, "{senec_field} <> '#{SensorMappings::SENEC_TOTAL_FIELD}'", reader) if reader

        page = {
          'name' => 'p_senec_field',
          'title' => Base.localized(en: 'SENEC measurement', de: 'SENEC-Messwert'),
          'elements' => [element],
        }
        survey['pages'].insert(1, page)
      end

      def refuse!(element, expression, reader)
        key = "sensors.#{reader}"
        element['validators'] = [
          {
            'type' => 'expression',
            'expression' => expression,
            'text' => Base.localized(
              en: "The total generation of SENEC is already assigned to \"#{I18n.t(key, locale: :en)}\".",
              de: "Die Gesamterzeugung von SENEC ist bereits „#{I18n.t(key, locale: :de)}“ zugeordnet.",
            ),
          },
        ]
      end

      def field_element
        {
          'type' => 'radiogroup',
          'name' => 'senec_field',
          'visibleIf' => "{source} = 'senec'",
          'isRequired' => true,
          'title' => Base.localized(
            en: 'Which measurement should be taken?',
            de: 'Welcher Messwert soll entnommen werden?',
          ),
          'choices' => [string_choice, total_choice],
          'defaultValue' => string_field,
        }
      end

      def string_field
        SensorMappings.default_field(sensor_name, 'senec')
      end

      def string_choice
        number = sensor_name.delete_prefix('inverter_power_')

        {
          'value' => string_field,
          'text' => Base.localized(
            en: "String #{number}\n\nThe normal case: the power of this string.",
            de: "String #{number}\n\nDer Normalfall: die Leistung dieses Strings.",
          ),
        }
      end

      def total_choice
        {
          'value' => SensorMappings::SENEC_TOTAL_FIELD,
          'text' => Base.localized(
            en: "Total generation\n\nOnly useful with an additional balcony power plant as a PV generator " \
                'of its own. Reads all strings of SENEC together.',
            de: "Gesamterzeugung\n\nNur sinnvoll mit einem zusätzlichen Steckersolargerät als eigenem " \
                'PV-Erzeuger. Liest alle Strings von SENEC zusammen.',
          ),
        }
      end
    end
  end
end
