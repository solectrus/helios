module Surveys
  # Fills the MQTT mapping pages of a survey from the shared MqttFields
  # fragments, and adds what only the server can decide: which mappings this
  # entry may read in a formula, which names are still free, and whether its
  # own name is read elsewhere.
  #
  # Both surveys that carry a mapping use this: the sensor survey (source =
  # mqtt, fields prefixed with `mqtt_`) and the standalone mqtt_topic survey.
  # They differ only in how their pages are named, how MqttFields is
  # configured, and which entry is being edited, so all three are arguments.
  class MqttPages
    # What each page explains. The same in both surveys, so it lives here
    # rather than twice in the JSON, where a copy edit would reach one survey
    # alone. The titles do differ (the sensor survey prefixes them with MQTT)
    # and stay in the JSON.
    DESCRIPTIONS = {
      kind: Base.localized(
        en: 'The value either comes from a topic or is calculated from other mappings.',
        de: 'Der Wert stammt entweder aus einem Topic oder wird aus anderen Zuordnungen berechnet.',
      ),
      extraction_method: Base.localized(
        en: 'Define how a measurement is derived from the received message.',
        de: 'Lege fest, wie aus der empfangenen Nachricht ein Messwert gewonnen wird.',
      ),
      extraction_value: Base.localized(
        en: 'Details of value extraction, depending on the kind chosen before.',
        de: 'Feinheiten der Wertgewinnung, abhängig von der zuvor gewählten Art.',
      ),
      filters: Base.localized(
        en: 'Optional filters to discard outliers or implausible values before storing.',
        de: 'Optionale Filter, um Ausreißer oder unplausible Werte vor dem Speichern zu verwerfen.',
      ),
      name: Base.localized(
        en: 'A name makes this value readable by the formula of a calculated mapping.',
        de: 'Ein Name macht diesen Wert für die Formel einer berechneten Zuordnung lesbar.',
      ),
      write: Base.localized(
        en: 'Optional settings for how often a value is stored in InfluxDB.',
        de: 'Optionale Einstellungen, wie oft ein Wert in InfluxDB abgelegt wird.',
      ),
    }.freeze

    # `pages` maps each logical page to the name it carries in the survey JSON.
    # `key` identifies the entry in the MappingGraph.
    def initialize(fields:, key:, pages:)
      @fields = fields
      @key = key
      @pages = pages
    end

    def call(survey)
      elements_by_page.each do |logical, elements|
        # A page the survey template does not carry is skipped, not created.
        page = survey['pages']&.find { |candidate| candidate['name'] == pages.fetch(logical) }
        next unless page

        # A page whose questions all fell away (the write behavior outside the
        # development channel) would remain as a step with a description and
        # nothing to answer, so it goes.
        if elements.empty?
          survey['pages'].delete(page)
          next
        end

        page['description'] = DESCRIPTIONS.fetch(logical)
        page['elements'] = elements
      end
    end

    private

    attr_reader :fields, :key, :pages

    def elements_by_page
      {
        kind: [fields.kind_radio(referencable)],
        extraction_method: [fields.extraction_method_radio],
        extraction_value: extraction_value_elements,
        filters: fields.filter_inputs,
        name: name_elements,
        write: fields.write_behavior_inputs,
      }
    end

    # The data type applies to both kinds, so it closes the page below the
    # inputs that belong to one kind alone.
    def extraction_value_elements
      [*fields.computed_inputs(referencable), *fields.extraction_value_inputs, fields.type_dropdown]
    end

    def name_elements
      fields.name_inputs(
        used_by_others: graph.names_used_by_others(key),
        dependents: graph.dependents_of(graph.name_of(key)),
      )
    end

    def graph
      # Fully qualified: inside Surveys, `Mqtt` would resolve to Surveys::Mqtt
      @graph ||= ::Mqtt::MappingGraph.new(Configuration.current)
    end

    def referencable
      @referencable ||= graph.referencable_from(key)
    end
  end
end
