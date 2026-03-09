module Configurations
  class ChaptersController < ApplicationController
    before_action :set_configuration

    def new
      kind = params[:kind]

      unless Chapter.valid_kind?(kind)
        return redirect_to configuration_path
      end

      render ChapterForm::Component.new(kind:)
    end

    def edit
      chapter = find_chapter
      render ChapterForm::Component.new(chapter:)
    end

    def create
      kind = params[:kind]

      unless Chapter.valid_kind?(kind)
        return redirect_to configuration_path
      end

      if Chapter.singleton_kind?(kind)
        chapter = @configuration.chapters.create!(kind:, name: kind, data: {})
        redirect_to edit_configuration_chapter_path(chapter)
      else
        data = chapter_params
        return unless data

        name = data.delete('name')
        @configuration.chapters.create!(kind:, name:, data:)
        redirect_to configuration_path
      end
    end

    def update
      chapter = find_chapter
      data = chapter_params
      return unless data

      if chapter.device?
        name = data.delete('name')
        chapter.update!(name:, data:)
      else
        chapter.update!(data:)
      end

      redirect_to configuration_path
    end

    def destroy
      chapter = find_chapter
      chapter.destroy!
      redirect_to configuration_path
    end

    private

    def set_configuration
      @configuration = Configuration.current
    end

    def find_chapter
      @configuration.chapters.find(params[:id])
    end

    def chapter_params
      JSON.parse(params.require(:chapter))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end
  end
end
