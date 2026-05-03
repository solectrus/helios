module Surveys
  # Shared element fragments for the MQTT mapping schema. Used by both the
  # sensor survey (when source = mqtt, fields prefixed with `mqtt_`) and the
  # standalone mqtt_topic survey (no prefix). Single source of truth for the
  # data-type choices, the extraction-mode radio, the conditional value
  # inputs, and the optional min/max/null_to_zero filters.
  class MqttFields
    # Keys that hold an extracted-value definition in a persisted topic.
    # `plain` is the implicit fallback (no key set) and is not listed here.
    EXTRACTION_KEYS = %w[json_key json_path json_formula formula].freeze
    EXTRACTION_MODES = ['plain', *EXTRACTION_KEYS].freeze
    NUMERIC_TYPES = %w[float integer].freeze

    EXTRACTION_CHOICE_TEXTS = {
      'plain' => {
        en: "Plain\n\nUse the payload value as-is",
        de: "Unverändert\n\nPayload-Wert ohne Transformation übernehmen",
      },
      'json_key' => {
        en: "JSON key\n\nFrom flat JSON by key, e.g. power",
        de: "JSON-Schlüssel\n\nAus flachem JSON per Schlüssel, z.B. power",
      },
      'json_path' => {
        en: "JSON path\n\nFrom nested JSON by JSONPath, e.g. $.sensor.temp",
        de: "JSON-Path\n\nAus verschachteltem JSON per JSONPath, z.B. $.sensor.temp",
      },
      'json_formula' => {
        en: "JSON formula\n\nFormula over JSON values, e.g. round({power} / 1000)",
        de: "JSON-Formel\n\nFormel über JSON-Werte, z.B. round({power} / 1000)",
      },
      'formula' => {
        en: "Formula\n\nFormula over the full payload, e.g. round({value} * 1000)",
        de: "Formel\n\nFormel über die komplette Payload, z.B. round({value} * 1000)",
      },
    }.freeze

    def initialize(prefix: '')
      @prefix = prefix
    end

    def field(key)
      "#{prefix}#{key}"
    end

    def type_dropdown(name: field('type'))
      {
        'type' => 'dropdown',
        'name' => name,
        'title' => Base.localized(en: 'Data type', de: 'Datentyp'),
        'isRequired' => true,
        'defaultValue' => 'float',
        'choices' => type_choices,
      }
    end

    def extraction_method_radio(name: field('extraction_method'))
      {
        'type' => 'radiogroup',
        'name' => name,
        'title' => Base.localized(
          en: 'How is the value extracted from the payload?',
          de: 'Wie wird der Messwert aus der Payload gewonnen?',
        ),
        'isRequired' => true,
        'defaultValue' => 'plain',
        'choices' => extraction_choices,
      }
    end

    def extraction_value_inputs(method_field: field('extraction_method'))
      [
        json_key_input(method_field),
        json_path_input(method_field),
        json_formula_input(method_field),
        formula_input(method_field),
      ]
    end

    def filter_inputs
      [min_input, max_input, null_to_zero_input]
    end

    private

    attr_reader :prefix

    def type_choices
      [
        choice('float', en: 'Floating point (float)', de: 'Gleitkommazahl (float)'),
        choice('integer', en: 'Integer', de: 'Ganzzahl (integer)'),
        choice('string', en: 'String', de: 'Zeichenkette (string)'),
        choice('boolean', en: 'Boolean', de: 'Wahrheitswert (boolean)'),
      ]
    end

    def extraction_choices
      EXTRACTION_MODES.map { |mode| choice(mode, **EXTRACTION_CHOICE_TEXTS.fetch(mode)) }
    end

    def choice(value, en:, de:) # rubocop:disable Naming/MethodParameterName
      { 'value' => value, 'text' => Base.localized(en:, de:) }
    end

    def json_key_input(method_field)
      {
        'type' => 'text',
        'name' => field('json_key'),
        'visibleIf' => "{#{method_field}} = 'json_key'",
        'isRequired' => true,
        'title' => Base.localized(en: 'JSON key', de: 'JSON-Schlüssel'),
        'description' => Base.localized(
          en: 'Name of the field in a flat JSON object',
          de: 'Name des Felds im flachen JSON-Objekt',
        ),
        'placeholder' => Base.localized(
          en: 'e.g. power or DHW tank temp. (R5T)',
          de: 'z.B. power oder DHW tank temp. (R5T)',
        ),
      }
    end

    def json_path_input(method_field)
      {
        'type' => 'text',
        'name' => field('json_path'),
        'visibleIf' => "{#{method_field}} = 'json_path'",
        'isRequired' => true,
        'title' => Base.localized(en: 'JSONPath expression', de: 'JSONPath-Ausdruck'),
        'description' => Base.localized(
          en: 'Starts with $, e.g. $.sensor.temp or $.ccp[2]',
          de: 'Beginnt mit $, z.B. $.sensor.temp oder $.ccp[2]',
        ),
        'placeholder' => '$.sensor.temp',
      }
    end

    def json_formula_input(method_field)
      {
        'type' => 'text',
        'name' => field('json_formula'),
        'visibleIf' => "{#{method_field}} = 'json_formula'",
        'isRequired' => true,
        'title' => Base.localized(en: 'JSON formula', de: 'JSON-Formel'),
        'description' => Base.localized(
          en: 'Reference JSON values in braces, e.g. round({power} / 1000)',
          de: 'JSON-Werte in geschweiften Klammern referenzieren, z.B. round({power} / 1000)',
        ),
        'placeholder' => 'round({power} / 1000)',
      }
    end

    def formula_input(method_field)
      {
        'type' => 'text',
        'name' => field('formula'),
        'visibleIf' => "{#{method_field}} = 'formula'",
        'isRequired' => true,
        'title' => Base.localized(en: 'Formula', de: 'Formel'),
        'description' => Base.localized(
          en: '{value} represents the full payload, e.g. round({value} * 1000)',
          de: '{value} steht für die komplette Payload, z.B. round({value} * 1000)',
        ),
        'placeholder' => 'round({value} * 1000)',
      }
    end

    def min_input
      {
        'type' => 'text',
        'inputType' => 'number',
        'name' => field('min'),
        'title' => Base.localized(en: 'Minimum value', de: 'Minimalwert'),
        'description' => Base.localized(
          en: 'Values below are discarded (leave empty for no limit)',
          de: 'Kleinere Werte werden verworfen (leer lassen für keine Grenze)',
        ),
      }
    end

    def max_input
      {
        'type' => 'text',
        'inputType' => 'number',
        'name' => field('max'),
        'title' => Base.localized(en: 'Maximum value', de: 'Maximalwert'),
        'description' => Base.localized(
          en: 'Values above are discarded (leave empty for no limit)',
          de: 'Größere Werte werden verworfen (leer lassen für keine Grenze)',
        ),
      }
    end

    def null_to_zero_input
      {
        'type' => 'boolean',
        'name' => field('null_to_zero'),
        'title' => Base.localized(en: 'Store NULL as 0', de: 'NULL als 0 speichern'),
        'description' => Base.localized(
          en: 'Empty or NULL values are stored as 0 in InfluxDB',
          de: 'Leere oder NULL-Werte werden als 0 in InfluxDB gespeichert',
        ),
        'defaultValue' => false,
      }
    end
  end
end
