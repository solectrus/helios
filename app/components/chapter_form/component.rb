module ChapterForm
  class Component < ViewComponent::Base
    attr_reader :chapter, :kind

    def initialize(chapter: nil, kind: nil)
      super()
      @chapter = chapter
      @kind = kind || chapter&.kind
    end

    def new_record?
      chapter.nil?
    end

    def form_url
      if new_record?
        helpers.configuration_chapters_path
      else
        helpers.configuration_chapter_path(chapter)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end

    def survey_url
      helpers.configuration_survey_path(@kind, format: :json)
    end

    def chapter_data_json
      return '{}' if new_record?

      data = chapter.data || {}
      data = data.merge('name' => chapter.name) if chapter.device?
      data.to_json
    end
  end
end
