class StartsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_consent
  before_action :redirect_if_already_imported

  def show; end

  def create
    StackBackup.create!
    import_existing_config!

    redirect_to services_path
  end

  private

  def import_existing_config!
    reader = Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
    Import::ConfigurationImporter.new(reader).import!
  end

  def redirect_if_already_imported
    redirect_to services_path if config_yaml_exists?
  end
end
