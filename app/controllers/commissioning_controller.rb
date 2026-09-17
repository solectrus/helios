# The screen that asks for the one answer an installation cannot start
# without. HELIOS has no default for it and nothing to derive it from, so it
# asks straight away instead of letting the user hunt for the form: every
# other screen waits behind ApplicationController#require_commissioning until
# this is saved. That gate is also what lets the Settings screen show plain
# chips, with no sign marking one of them as still empty.
#
# The page is reachable exactly while something is open, and it renders the
# survey that owns the open question (see #setting).
class CommissioningController < ApplicationController
  include SurveyData
  include SettingPersistence

  helper_method :setting, :setting_data

  skip_before_action :require_commissioning
  before_action :set_configuration
  before_action :redirect_if_complete

  def show; end

  def create
    data = survey_data
    return unless data

    persist_setting(data)
    finish_setting_save!

    # The answers just saved leave an installation without a single sensor, so
    # the Sensors screen has nothing to show yet. The data sources are what it
    # waits for, and that is where the configuration continues.
    redirect_to datasources_path
  end

  private

  # The survey that owns the open question. Exactly one of the two applies per
  # mode: the commissioning date belongs to the dashboard, and a host that runs
  # none of its own needs the address of the database it writes to, which the
  # deployment survey asks for along with the mode.
  def setting
    @configuration.collectors_only? ? 'deployment' : 'system_general'
  end

  # What the configuration already carries for that survey. A fresh
  # installation brings nothing, an import brings the timezone it ran on, and
  # the deployment survey has to show the mode that is stored or the form
  # would offer to switch it back.
  def setting_data
    @configuration.setting_data(setting)
  end

  def set_configuration
    @configuration = Configuration.current
  end

  def redirect_if_complete
    return if @configuration.commissioning_incomplete?

    redirect_to helpers.configuration_entry_path
  end
end
