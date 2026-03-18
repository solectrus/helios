module KindSection
  class Component < ViewComponent::Base
    ICONS = {
      'inverter' => 'fa-solar-panel',
      'battery' => 'fa-car-battery',
      'wallbox' => 'fa-charging-station',
      'car' => 'fa-car',
      'heatpump' => 'fa-fan',
      'consumer' => 'fa-plug',
      'forecast' => 'fa-cloud-sun',
      'system' => 'fa-gear',
      'reverse_proxy' => 'fa-shield-halved',
      'backup' => 'fa-cloud-arrow-up',
      'sensors' => 'fa-gauge',
    }.freeze

    attr_reader :kind, :chapters

    def initialize(kind:, chapters:)
      super()
      @kind = kind
      @chapters = chapters
    end

    def device?
      Chapter.device_kind?(kind)
    end

    def singleton?
      Chapter.singleton_kind?(kind)
    end

    def icon
      ICONS[kind] || 'fa-circle-question'
    end

    def title
      I18n.t("configurations.chapters.#{kind}.title")
    end

    def add_path
      helpers.new_configuration_chapter_path(kind:)
    end

    def singleton_chapter
      chapters.first
    end

    def singleton_configured?
      singleton_chapter&.completed? || false
    end
  end
end
