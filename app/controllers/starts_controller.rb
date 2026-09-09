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
    @external_ingest_sensors = importer.external_ingest_sensors if @unsupported_services.empty?
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
  end

  def create
    adopt_stack!
    redirect_to services_path
  rescue Import::UnsupportedServicesError => e
    @unsupported_services = e.services
    render :show, status: :unprocessable_content
  rescue Import::StackReader::Error => e
    @compose_error = e.detail
    render :show, status: :unprocessable_content
  end

  private

  # Refuse before touching anything: HELIOS regenerates compose.yaml in full
  # and would silently drop what it can't reproduce. Then back up and adopt.
  def adopt_stack!
    Import::CompatibilityCheck.new(stack_reader).call!

    StackBackup.create!
    # Baseline the adopted stack's compose config *before* the rewrite below
    # replaces it. The imported containers keep running with their pre-import
    # definitions (e.g. without the influx-backup-staging mount, issue #291);
    # only a pre-rewrite baseline lets AffectedServices flag them as
    # "restart required" instead of lazily adopting the rewritten config.
    Orchestration::AffectedServices.seed_baseline_if_missing!
    importer.import!
    Export::Builder.new(Configuration.current).write!
    Orchestration::AffectedServices.invalidate_config_hashes
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
