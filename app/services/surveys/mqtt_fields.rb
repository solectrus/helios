module Surveys
  # Shared element fragments for the MQTT mapping schema. Used by both the
  # sensor survey (when source = mqtt, fields prefixed with `mqtt_`) and the
  # standalone mqtt_topic survey (no prefix). Single source of truth for the
  # topic-or-calculated switch, the data-type choices, the extraction-mode
  # radio, the conditional value inputs, the optional min/max/null_to_zero
  # filters, and the naming and write-behavior options of mqtt-collector 0.8.
  #
  # Everything that differs between the two surveys is answered once, at
  # construction: the field prefix, the survey-wide `guard` every condition is
  # ANDed with, and the two field names that predate the prefix convention.
  # The fragments themselves are therefore identical for both callers.
  #
  # Long for a class, but deliberately one file: it is a flat catalogue of
  # survey fragments, and splitting it would spread the mapping schema over
  # several places again.
  class MqttFields # rubocop:disable Metrics/ClassLength
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

    # The UI-only answers that describe a stored mapping: which kind it is, how
    # its value is extracted, and the formula of a calculated one. These
    # questions exist for the form alone, so `Configuration#fold_computed_formula`
    # and the field slices drop them again on save. Both surveys derive them
    # the same way, only under their own field names.
    def self.ui_state(data, prefix: '', method_field: 'extraction_method')
      computed = data["#{prefix}topic"].blank?

      state = {
        "#{prefix}kind" => computed ? 'computed' : 'topic',
        method_field => EXTRACTION_KEYS.find { |key| data["#{prefix}#{key}"].present? } || 'plain',
      }
      state["#{prefix}computed_formula"] = data["#{prefix}formula"] if computed
      state
    end

    # `guard` is a survey-wide precondition every generated condition is ANDed
    # with (the sensor survey only shows these fields for source = mqtt).
    # `type_field` and `method_field` name the two questions the sensor survey
    # calls differently than the prefix would suggest. `skip_write` says whether
    # this survey offers the option at all: only a standalone entry may skip
    # writing, a sensor names an InfluxDB target by definition.
    def initialize(prefix: '', guard: nil, type_field: nil, method_field: nil, skip_write: false)
      @prefix = prefix
      @guard = guard
      @type_field = type_field || field('type')
      @method_field = method_field || field('extraction_method')
      @skip_write = skip_write
    end

    # Where a mapping gets its value from. A calculated one has no topic and
    # reads other mappings by name, so without a single name to read the choice
    # is offered but disabled, with the reason in its place.
    def kind_radio(names)
      visible_if(
        {
          'type' => 'radiogroup',
          'name' => field('kind'),
          'title' => Base.localized(en: 'Where does the value come from?', de: 'Woher stammt der Wert?'),
          'isRequired' => true,
          'defaultValue' => 'topic',
          'choices' => [
            choice('topic', en: "Topic\n\nRead from a topic on the broker",
                            de: "Topic\n\nAus einem Topic des Brokers gelesen"),
            computed_choice(names),
          ],
        },
        guard,
      )
    end

    # The data type applies to both kinds, so it carries no kind condition.
    def type_dropdown
      {
        'type' => 'dropdown',
        'name' => type_field,
        'title' => Base.localized(en: 'Data type', de: 'Datentyp'),
        'isRequired' => true,
        'defaultValue' => 'float',
        'choices' => type_choices,
      }
    end

    def extraction_method_radio
      {
        'type' => 'radiogroup',
        'name' => method_field,
        'visibleIf' => topic_condition,
        'title' => Base.localized(
          en: 'How is the value extracted from the payload?',
          de: 'Wie wird der Messwert aus der Payload gewonnen?',
        ),
        'isRequired' => true,
        'defaultValue' => 'plain',
        'choices' => extraction_choices,
      }
    end

    # All four describe a payload, which only a topic delivers.
    def extraction_value_inputs
      [json_key_input, json_path_input, json_formula_input, formula_input].map do |input|
        visible_if(input, join(topic_condition, input['visibleIf']))
      end
    end

    # The formula of a calculated mapping, next to the names it may read. Kept
    # apart from `formula`, which transforms the payload of a topic via
    # {value}: the two accept different references, so one question could not
    # validate both. Both end up in the collector's single MAPPING_X_FORMULA,
    # folded together on save.
    def computed_inputs(names)
      return [] if names.empty?

      [reference_hint(names), computed_formula_input(names)]
    end

    # Min/max/null_to_zero only apply to numeric payloads, so they are gated on
    # the data type. The condition sits on every input rather than on the
    # enclosing page: SurveyJS clears an invisible value (clearInvisibleValues:
    # onHidden) only when the question's own `visible` flips. A page-level gate
    # hides the inputs but keeps their values, so switching the type from float
    # to string used to leave a stale NULL_TO_ZERO=true in the export. A page
    # whose questions are all invisible disappears on its own, so dropping the
    # page condition costs nothing.
    #
    def filter_inputs
      [min_input, max_input, null_to_zero_input].map { |input| input.merge('visibleIf' => numeric_condition) }
    end

    # How often a mapping is written, rather than what is written. Averaging
    # needs a number, so AGGREGATE_INTERVAL is gated on the data type the same
    # way the filters are; deduplication works for every type.
    #
    # As in `filter_inputs`, every condition sits on the question itself, so
    # clearInvisibleValues drops a value the collector would refuse: an
    # aggregation interval on a string mapping, or a heartbeat without
    # deduplication.
    def write_behavior_inputs
      [
        (visible_if(skip_write_input, named_condition) if skip_write),
        *throttle_inputs,
      ].compact
    end

    # The alias a formula reads this mapping by. Only a named mapping can be
    # referenced, so MAX_AGE and SKIP_WRITE hang off this field.
    #
    # `used_by_others` are the names other mappings already carry, `dependents`
    # the entries whose formula reads this one. While something reads it, the
    # name may be changed (HELIOS carries the formulas along) but not dropped,
    # so the field turns mandatory.
    def name_inputs(used_by_others: [], dependents: [])
      [
        name_input(used_by_others, dependents),
        visible_if(max_age_input, named_condition),
      ]
    end

    private

    attr_reader :prefix, :guard, :type_field, :method_field, :skip_write

    def field(key)
      "#{prefix}#{key}"
    end

    # Adds a visibility condition, or leaves the element ungated when there is
    # nothing to gate it on.
    def visible_if(element, condition)
      condition.present? ? element.merge('visibleIf' => condition) : element
    end

    def join(*conditions)
      conditions.compact_blank.join(' and ')
    end

    def and_guard(condition)
      join(guard, condition)
    end

    # Memoized: the instance does not change after construction, and each of
    # these is asked for once per input of a page.
    def topic_condition
      @topic_condition ||= and_guard("{#{field('kind')}} = 'topic'")
    end

    def computed_condition
      @computed_condition ||= and_guard("{#{field('kind')}} = 'computed'")
    end

    def numeric_condition
      @numeric_condition ||= and_guard("(#{NUMERIC_TYPES.map { |type| "{#{type_field}} = '#{type}'" }.join(' or ')})")
    end

    def dedup_condition
      and_guard("{#{field('dedup')}} = true")
    end

    def named_condition
      and_guard("{#{field('name')}} notempty")
    end

    # An option that only controls writing has no effect on a mapping that is
    # never written, and the collector refuses the combination outright. Only
    # added where the survey offers SKIP_WRITE at all, so no condition names a
    # question that does not exist.
    def written_condition
      "{#{field('skip_write')}} <> true" if skip_write
    end

    # How often a written value reaches InfluxDB, each gated on the mapping
    # being written at all.
    def throttle_inputs
      written = written_condition

      [
        visible_if(aggregate_interval_input, join(numeric_condition, written)),
        visible_if(dedup_input, join(guard, written)),
        visible_if(heartbeat_interval_input, join(dedup_condition, written)),
      ]
    end

    def name_input(used_by_others, dependents)
      input = {
        'type' => 'text',
        'name' => field('name'),
        'title' => Base.localized(en: 'Name for formulas', de: 'Name für Formeln'),
        'description' => name_description(dependents),
        'placeholder' => Base.localized(en: 'e.g. wallbox_power', de: 'z.B. wallbox_power'),
        'validators' => [name_format_validator, name_uniqueness_validator(used_by_others)],
      }
      input['isRequired'] = true if dependents.any?
      visible_if(input, guard)
    end

    def computed_choice(names)
      option = choice(
        'computed',
        en: "Calculated\n\nCalculated from other mappings by a formula",
        de: "Berechnet\n\nPer Formel aus anderen Zuordnungen berechnet",
      )
      return option if names.any?

      option.merge(
        'enableIf' => 'false',
        'text' => Base.localized(
          en: "Calculated\n\nNeeds at least one mapping with a name to read",
          de: "Berechnet\n\nBraucht mindestens eine Zuordnung mit einem Namen",
        ),
      )
    end

    def reference_hint(names)
      {
        'type' => 'html',
        'name' => field('reference_hint'),
        'visibleIf' => computed_condition,
        'html' => Base.localized(
          en: "<p>Available names, to be used in braces: <strong>#{names.join(', ')}</strong></p>",
          de: '<p>Verfügbare Namen, in geschweiften Klammern zu verwenden: ' \
              "<strong>#{names.join(', ')}</strong></p>",
        ),
      }
    end

    def computed_formula_input(names)
      {
        'type' => 'text',
        'name' => field('computed_formula'),
        'visibleIf' => computed_condition,
        'isRequired' => true,
        'title' => Base.localized(en: 'Formula', de: 'Formel'),
        'description' => Base.localized(
          en: 'Reads other mappings by their name, in braces',
          de: 'Liest andere Zuordnungen über ihren Namen, in geschweiften Klammern',
        ),
        'placeholder' => '{house_power} - {wallbox_power}',
        'validators' => [reference_validator(names)],
      }
    end

    # Restricts a formula to references the collector can resolve. Building the
    # pattern from the allowed names catches a typo in the form instead of
    # letting it stop the collector at startup, where only its own log shows
    # the reason. Requiring at least one group mirrors the collector's rule
    # that a formula without a reference is a constant.
    def reference_validator(names)
      alternation = names.map { |name| Regexp.escape(name) }.join('|')

      {
        'type' => 'regex',
        'regex' => "^[^{]*(\\{(#{alternation})\\}[^{]*)+$",
        'text' => Base.localized(
          en: "Only these names can be used, in braces: #{names.join(', ')}",
          de: "Nur diese Namen sind hier verwendbar, in geschweiften Klammern: #{names.join(', ')}",
        ),
      }
    end

    def name_description(dependents)
      if dependents.empty?
        return Base.localized(
          en: 'Only needed when a formula reads this value',
          de: 'Nur nötig, wenn eine Formel diesen Wert liest',
        )
      end

      Base.localized(
        en: "Read by: #{dependents.join(', ')}. A new name is carried into those formulas.",
        de: "Wird gelesen von: #{dependents.join(', ')}. Ein neuer Name wird dort nachgezogen.",
      )
    end

    # The collector restricts a name to what survives its formula parser
    # unchanged, which lowercases and replaces every other character.
    def name_format_validator
      {
        'type' => 'regex',
        'regex' => "^#{::Mqtt::MappingGraph::NAME_FORMAT.source}$",
        'text' => Base.localized(
          en: 'Lowercase letters, digits and underscores only, and not starting with a digit',
          de: 'Nur Kleinbuchstaben, Ziffern und Unterstriche, nicht mit einer Ziffer beginnend',
        ),
      }
    end

    # "value" is the collector's own placeholder for the payload of a mapping
    # with a topic, so it cannot name a mapping.
    def name_uniqueness_validator(used_by_others)
      taken = used_by_others + ['value']
      condition = taken.map { |name| "{#{field('name')}} <> '#{name}'" }.join(' and ')

      {
        'type' => 'expression',
        'expression' => "{#{field('name')}} empty or (#{condition})",
        'text' => Base.localized(
          en: 'This name is already in use',
          de: 'Dieser Name ist bereits vergeben',
        ),
      }
    end

    def max_age_input
      {
        'type' => 'text',
        'inputType' => 'number',
        'min' => 1,
        'name' => field('max_age'),
        'title' => Base.localized(en: 'Maximum age (seconds)', de: 'Höchstalter (Sekunden)'),
        'description' => Base.localized(
          en: 'After this time the value counts as unknown in a formula, so an outage ' \
              'leaves a gap instead of a wrong number',
          de: 'Nach dieser Zeit gilt der Wert in einer Formel als unbekannt, damit ein ' \
              'Ausfall eine Lücke hinterlässt statt einer falschen Zahl',
        ),
        'placeholder' => Base.localized(en: 'e.g. 300', de: 'z.B. 300'),
      }
    end

    def skip_write_input
      {
        'type' => 'boolean',
        'name' => field('skip_write'),
        'title' => Base.localized(en: 'Keep in memory only', de: 'Nur im Speicher halten'),
        'description' => Base.localized(
          en: 'The value stays available to formulas but is not stored in InfluxDB',
          de: 'Der Wert steht Formeln zur Verfügung, wird aber nicht in InfluxDB gespeichert',
        ),
        'defaultValue' => false,
      }
    end

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

    def json_key_input
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

    def json_path_input
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

    def json_formula_input
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

    def formula_input
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
        'validators' => [value_only_validator],
      }
    end

    # A mapping with a topic knows one reference, the payload itself. From
    # 0.8.0 the collector refuses to start on any other name here, so the form
    # catches it instead of the startup log. Requiring at least one {value}
    # mirrors the rule that a formula without a reference is a constant.
    def value_only_validator
      {
        'type' => 'regex',
        'regex' => '^[^{]*(\\{value\\}[^{]*)+$',
        'text' => Base.localized(
          en: 'Only {value} can be used here, the name of another mapping is not resolved.',
          de: 'Hier ist nur {value} verwendbar, der Name einer anderen Zuordnung wird nicht aufgelöst.',
        ),
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

    def aggregate_interval_input
      {
        'type' => 'text',
        'inputType' => 'number',
        'min' => 1,
        'name' => field('aggregate_interval'),
        'title' => Base.localized(en: 'Averaging interval (seconds)', de: 'Mittelungsintervall (Sekunden)'),
        'description' => Base.localized(
          en: 'Only needed for topics that send very fast: stores the average over this ' \
              'many seconds instead of every single value',
          de: 'Nur bei sehr schnell sendenden Topics nötig: speichert den Mittelwert dieser ' \
              'Sekundenzahl statt jeden Einzelwert',
        ),
        'placeholder' => Base.localized(en: 'e.g. 60', de: 'z.B. 60'),
      }
    end

    def dedup_input
      {
        'type' => 'boolean',
        'name' => field('dedup'),
        'title' => Base.localized(en: 'Store changed values only', de: 'Nur geänderte Werte speichern'),
        'description' => Base.localized(
          en: 'A repeated value is skipped, apart from a regular heartbeat',
          de: 'Ein wiederholter Wert wird übersprungen, abgesehen von einem regelmäßigen Lebenszeichen',
        ),
        'defaultValue' => false,
      }
    end

    # The collector only warns when the heartbeat is not longer than the
    # averaging interval, and keeps running. HELIOS generates the file, so a
    # combination without effect is refused right here. An empty field counts
    # as the collector's default, which is short enough to be pointless next
    # to an averaging interval of 60 seconds or more.
    def heartbeat_interval_input
      {
        'type' => 'text',
        'inputType' => 'number',
        'min' => 1,
        'name' => field('heartbeat_interval'),
        'title' => Base.localized(en: 'Heartbeat interval (seconds)', de: 'Lebenszeichen-Intervall (Sekunden)'),
        'description' => Base.localized(
          en: 'A repeated value is stored again after this time to signal continued ' \
              "activity (default: #{ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL})",
          de: 'Ein wiederholter Wert wird nach dieser Zeit erneut gespeichert, um ' \
              "anhaltende Aktivität zu signalisieren (Standard: #{ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL})",
        ),
        'placeholder' => Base.localized(en: 'e.g. 900', de: 'z.B. 900'),
        'validators' => [heartbeat_interval_validator],
      }
    end

    def heartbeat_interval_validator
      {
        'type' => 'expression',
        'expression' =>
          "{#{field('aggregate_interval')}} empty or " \
          "iif({#{field('heartbeat_interval')}} empty, #{ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL}, " \
          "{#{field('heartbeat_interval')}}) > {#{field('aggregate_interval')}}",
        'text' => Base.localized(
          en: 'The heartbeat interval must be longer than the averaging interval ' \
              "(default: #{ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL}), " \
              'otherwise every average is stored and nothing is left out.',
          de: 'Das Lebenszeichen-Intervall muss länger sein als das Mittelungsintervall ' \
              "(Standard: #{ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL}), " \
              'sonst wird jeder Mittelwert gespeichert und nichts ausgelassen.',
        ),
      }
    end
  end
end
