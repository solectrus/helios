module ChapterForm
  class Component < ViewComponent::Base
    attr_reader :chapter, :chapter_data

    def initialize(chapter:, chapter_data:)
      super()
      @chapter = chapter.to_s
      @chapter_data = chapter_data
    end

    def form_url
      helpers.configuration_chapter_path(chapter)
    end

    def survey_url
      helpers.configuration_chapter_path(chapter, format: :json)
    end

    def chapter_data_json
      chapter_data.to_json
    end
  end
end
