module Configurations
  class ChaptersController < ApplicationController
    skip_before_action :require_authentication # TODO: Remove after development

    before_action :set_configuration
    before_action :validate_chapter

    def show
      path = Rails.root.join("config/surveys/#{chapter_name}.json")

      if path.exist?
        render json: JSON.parse(path.read)
      else
        head :not_found
      end
    end

    def edit
      @chapter_data = @configuration.chapter(chapter_name)
    end

    def update
      @configuration.update_chapter(chapter_name, chapter_params)
      redirect_to configuration_path
    end

    private

    def set_configuration
      @configuration = Configuration.current
    end

    def validate_chapter
      return if Chapter::NAMES.include?(chapter_name)

      redirect_to configuration_path, alert: t('configurations.chapters.invalid_chapter')
    end

    def chapter_name
      params[:id]
    end

    def chapter_params
      JSON.parse(params.require(:chapter))
    end

    helper_method :chapter_name
  end
end
