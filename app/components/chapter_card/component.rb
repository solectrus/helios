module ChapterCard
  class Component < ViewComponent::Base
    with_collection_parameter :chapter

    ICONS = {
      'devices' => 'fa-microchip',
      'inverter' => 'fa-solar-panel',
      'wallbox' => 'fa-charging-station',
      'heatpump' => 'fa-fan',
      'mqtt' => 'fa-network-wired',
      'forecast' => 'fa-cloud-sun',
      'system' => 'fa-gear',
    }.freeze

    attr_reader :chapter, :configuration

    def initialize(chapter:, configuration:)
      super()
      @chapter = chapter.to_s
      @configuration = configuration
    end

    def completed?
      configuration.chapter_completed?(chapter)
    end

    def icon
      ICONS[chapter] || 'fa-circle-question'
    end

    def title
      I18n.t("configurations.chapters.#{chapter}.title")
    end

    def description
      I18n.t("configurations.chapters.#{chapter}.description")
    end

    def path
      helpers.edit_configuration_chapter_path(chapter)
    end
  end
end
