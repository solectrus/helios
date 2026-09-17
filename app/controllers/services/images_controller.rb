module Services
  class ImagesController < BaseController
    before_action :reject_helios
    before_action :require_configuration_complete

    def update
      config_keys = Export::Compose.find_service(service_name)&.config_keys
      recommended = DockerImages.recommended_for(service_name)
      return head :unprocessable_content unless config_keys && recommended
      # An unmanaged service of the same name (a Traefik HELIOS did not adopt,
      # for example) keeps its compose entry verbatim. Writing the image into
      # the managed section would change nothing the export renders.
      return head :unprocessable_content if Configuration.current.unmanaged_service?(service_name)

      apply_image!(config_keys, recommended)

      Orchestration::StackStatus.mark_starting!
      Orchestration::PendingOperations.set(service_name, :recreate)
      ComposeJob.perform_later(:recreate, service_name)
      respond_with_pending_status(status_bar: :starting)
    end

    private

    # Every service keeps its image in the top-level section its config_keys
    # name (`['dashboard']`, `['senec']`, …).
    def apply_image!(config_keys, new_image)
      configuration = Configuration.current
      section_key = config_keys.first
      section = configuration.setting_data(section_key).to_h
      section['image'] = new_image
      configuration.update(section_key, section)
    end
  end
end
