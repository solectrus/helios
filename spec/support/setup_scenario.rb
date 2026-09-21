require 'open3'

# Replays a recorded setup: the answers a user gives in the surveys of a fresh
# HELIOS, posted through the real controller. Drives the scenarios under
# spec/scenarios/setup/, which start at the state bootstrap/install.sh leaves
# behind.
#
# Each answer goes through the survey that HELIOS serves for it, run by
# survey-core in spec/support/survey_walk.mjs. The payload is therefore the one
# the form would post, not one this class builds: the survey resolves its own
# visibleIf, fills in the defaults of the questions the answers leave alone,
# and refuses a page it considers incomplete.
class SetupScenario
  # Raised for a scenario that no longer describes a setup a user can complete,
  # which is what a scenario claims it does.
  class RefusedError < StandardError; end

  WALKER = Rails.root.join('spec/support/survey_walk.mjs').freeze

  # Where a scenario keeps the three files the replay must produce. The other
  # two families spread them the way a real host does, which a scenario that
  # starts at no stack at all has no reason to imitate.
  EXPECTED_DIR = 'expected'.freeze

  # The state a real installation starts in: no config.yaml, and the two
  # secrets install.sh writes into .env and the compose file hands to the
  # helios service. HELIOS therefore asks for the password from the first
  # request on, and promotes both values into config.yaml on the first save.
  # Both are spelled out as obvious dummies, so nothing in a fixture can be
  # mistaken for a secret.
  SECRET_KEY_BASE = 'dummy-secret-key-base-for-setup-scenarios'.freeze
  ADMIN_PASSWORD = 'dummy-admin-password'.freeze

  # What HELIOS mints for itself, one fresh random value per installation (see
  # ConfigSchema::AUTO_GENERATED). install.sh cannot seed these, so a scenario
  # cannot pin them either without taking the minting out of the replay. Each
  # minted value is replaced by a placeholder afterwards instead.
  #
  # Replacement goes by value, not by field, so it keeps what the minting
  # decided: the four InfluxDB tokens carry one value (see
  # Export::Builder#link_influxdb_tokens!), so one placeholder reaches all four.
  MINTED_FIELDS = {
    'postgresql' => %w[password].freeze,
    'influxdb' => %w[password token_admin token_readwrite token_write token_read].freeze,
  }.freeze

  # The address the browser carries. HELIOS adopts it as `app_host` on the
  # first save (see Configurations::SettingsController#adopt_request_host!),
  # exactly as it does for a user who opens the UI by that name.
  DEFAULT_BROWSER_HOST = 'helios.local'.freeze

  def initialize(scenario_path)
    @scenario = YAML.safe_load_file(Pathname.new(scenario_path).join('answers.yml'), permitted_classes: [Date])
  end

  # Logs in and answers every survey, then replaces the minted secrets.
  # Returns the configuration the caller exports.
  def replay!
    with_install_env do
      submit('/session', password: ADMIN_PASSWORD)
      @scenario.fetch('answers').each { |step| answer(step) }
    end
    replace_minted_secrets!
    Configuration.current
  end

  private

  def session
    @session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |s|
      s.host! @scenario.fetch('browser_host', DEFAULT_BROWSER_HOST)
    end
  end

  # The environment the helios service runs in. Restored afterwards, so the
  # export the caller runs sees only what the replay wrote to config.yaml.
  def with_install_env
    previous = ENV.to_h.slice('SECRET_KEY_BASE', 'ADMIN_PASSWORD')
    ENV['SECRET_KEY_BASE'] = SECRET_KEY_BASE
    ENV['ADMIN_PASSWORD'] = ADMIN_PASSWORD
    yield
  ensure
    %w[SECRET_KEY_BASE ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  # Every screen answers with a redirect, a refused one included: a rejected
  # value goes back to the page that asked and carries the complaint in the
  # flash, an unauthenticated request goes to the login. Only the redirect the
  # controller picks for the screen itself counts as done.
  def submit(path, params)
    session.post(path, params:)
    response = session.response

    raise RefusedError, "#{path} answered #{response.status}" unless response.redirect?
    raise RefusedError, "#{path} was refused: #{session.flash[:alert]}" if session.flash[:alert].present?
    raise RefusedError, "#{path} was not authenticated" if response.location.end_with?('/session/new')
  end

  def answer(step)
    params = { setting: step.fetch('setting'), data: payload_for(step).to_json }
    params[:name] = step['name'] if step['name']

    submit('/configuration/settings', params)
  end

  # What the form would post for this step. The survey is fetched here rather
  # than ahead of time because Surveys::Base#customize! reads the
  # configuration: a later survey is shaped by the earlier answers.
  def payload_for(step)
    setting = step.fetch('setting')
    session.get("/configuration/surveys/#{setting}", params: { sensor: step['name'] }.compact)
    raise RefusedError, "No survey for '#{setting}'" unless session.response.ok?

    result = walk(JSON.parse(session.response.body), step.fetch('answers'))
    check(setting, result)
    result['data']
  end

  # Incompleteness first: a walk that gets stuck never reaches the questions
  # behind the page that stopped it, so every answer below would be reported as
  # unused too. The page that refused is the one to name.
  def check(setting, result)
    unless result['completed']
      raise RefusedError,
            "Survey '#{setting}' stayed incomplete: #{result['errors'].join(', ')}"
    end

    return if result['unused'].empty?

    raise RefusedError, "Survey '#{setting}' asks for no question named #{result['unused'].join(', ')}"
  end

  def walk(survey, answers)
    stdout, stderr, status = Open3.capture3(
      'bun', WALKER.to_s, stdin_data: { survey:, answers: }.to_json, chdir: Rails.root.to_s
    )
    raise RefusedError, "survey_walk.mjs failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  def replace_minted_secrets!
    config = Configuration.current
    placeholders = {}

    MINTED_FIELDS.each do |section, fields|
      values = config.send(section).to_h
      fields.each do |field|
        value = values[field]
        values[field] = placeholders[value] ||= "minted-#{section}-#{field.tr('_', '-')}" if value.present?
      end
      config.update(section, values)
    end
  end
end
