class StartsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_consent
  before_action :redirect_if_already_imported

  def show
    # Check upfront so the page can offer the import button only when the
    # whole stack is reproducible, instead of failing after the user clicks.
    return unless File.exist?(Compose.path)

    @unsupported_services = Import::CompatibilityCheck.new(stack_reader).unsupported_services
    # Only meaningful once every service is reproducible; skip the dry-run
    # otherwise (the services block is shown anyway).
    @ingest_conflict_sensors = importer.ingest_conflict_sensors if @unsupported_services.empty?
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
  end

  def create
    adopt_stack!
    redirect_to services_path
  rescue Import::UnsupportedServicesError => e
    @unsupported_services = e.services
    render :show, status: :unprocessable_content
  rescue Import::IngestExternalConflictError => e
    @ingest_conflict_sensors = e.sensors
    render :show, status: :unprocessable_content
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
    render :show, status: :unprocessable_content
  end

  private

  # Refuse before touching anything: HELIOS regenerates compose.yaml in full
  # and would silently drop what it can't reproduce — unknown services, or an
  # Ingest fed by an external source it can't reroute. Then back up and adopt.
  def adopt_stack!
    Import::CompatibilityCheck.new(stack_reader).call!

    conflict = importer.ingest_conflict_sensors
    raise Import::IngestExternalConflictError, conflict if conflict.any?

    StackBackup.create!
    importer.import!
    Export::Builder.new(Configuration.current).write!
  end

  def stack_reader
    @stack_reader ||= Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
  end

  def importer
    @importer ||= Import::ConfigurationImporter.new(stack_reader)
  end

  def redirect_if_already_imported
    redirect_to services_path if config_yaml_exists?
  end
end
