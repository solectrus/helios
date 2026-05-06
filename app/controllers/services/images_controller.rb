module Services
  class ImagesController < BaseController
    before_action :reject_helios

    def update
      config_keys = Export::Compose.find_service(service_name)&.config_keys
      recommended = DockerImages.recommended_for(service_name)
      return head :unprocessable_content unless config_keys && recommended

      apply_image!(config_keys, recommended)

      Orchestration::StackStatus.mark_starting!
      Orchestration::PendingOperations.set(service_name, :recreate)
      ComposeJob.perform_later(:recreate, service_name)
      respond_with_pending_status(status_bar: :starting)
    end

    private

    def apply_image!(config_keys, new_image)
      configuration = Configuration.current
      section_key = config_keys.first
      section = configuration.setting_data(section_key).to_h
      target = config_keys[1..].inject(section) do |node, key|
        node[key] ||= {}
        node[key]
      end
      target['image'] = new_image
      configuration.update(section_key, section)
    end
  end
end
