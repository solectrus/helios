class StartsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_consent
  before_action :redirect_if_already_imported

  def show
    # Check upfront so the page can offer the import button only when the
    # whole stack is reproducible, instead of failing after the user clicks.
    return unless File.exist?(Compose.path)

    @unsupported_services =
      Import::CompatibilityCheck.new(stack_reader).unsupported_services
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
  end

  def create
    # Refuse before touching anything: HELIOS regenerates compose.yaml in full
    # and would silently drop services it can't reproduce.
    Import::CompatibilityCheck.new(stack_reader).call!

    StackBackup.create!
    Import::ConfigurationImporter.new(stack_reader).import!
    Export::Builder.new(Configuration.current).write!

    redirect_to services_path
  rescue Import::UnsupportedServicesError => e
    @unsupported_services = e.services
    render :show, status: :unprocessable_content
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
    render :show, status: :unprocessable_content
  end

  private

  def stack_reader
    @stack_reader ||= Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
  end

  def redirect_if_already_imported
    redirect_to services_path if config_yaml_exists?
  end
end
