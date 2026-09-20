namespace :fixtures do
  # Recursively sort hash keys alphabetically.
  def deep_sort_keys(obj)
    case obj
    when Hash then obj.sort.to_h.transform_values { |v| deep_sort_keys(v) }
    when Array then obj.map { |e| deep_sort_keys(e) }
    else obj
    end
  end

  def regenerate_scenario(scenario_path)
    Current.configuration = nil
    [Configuration.path, Compose.path, Env.path].each { |p| FileUtils.rm_f(p) }

    config = import_scenario(scenario_path)
    dump_expected_fixtures(config, scenario_path)
  end

  # An export scenario starts at a config.yaml taken from a running HELIOS
  # instance instead of a foreign stack, so it replaces the import step with
  # the migration chain. Everything after that is the same.
  def regenerate_export_scenario(scenario_path)
    Current.configuration = nil
    [Configuration.path, Compose.path, Env.path].each { |p| FileUtils.rm_f(p) }

    FileUtils.mkdir_p(File.dirname(Configuration.path))
    FileUtils.cp(scenario_path.join('helios/config.yaml.bak'), Configuration.path)
    ConfigurationMigrator.run!
    Current.configuration = nil

    dump_expected_fixtures(Configuration.current, scenario_path)
  end

  def import_scenario(scenario_path)
    stack_reader = Import::StackReader.new(
      compose_path: compose_backup_path(scenario_path) || abort(missing_compose_backup_message(scenario_path)),
      env_path: scenario_path.join('.env.bak'),
    )
    Import::ConfigurationImporter.new(stack_reader).import!
  end

  # Locate the backup compose file next to an import scenario. Tries every
  # filename variant HELIOS accepts (compose.yaml, docker-compose.yaml,
  # docker-compose.yml) with a .bak suffix.
  def compose_backup_path(scenario_path)
    Compose::FILENAMES.lazy.map { |f| scenario_path.join("#{f}.bak") }.find(&:file?)
  end

  def missing_compose_backup_message(scenario_path)
    candidates = Compose::FILENAMES.map { |f| "#{f}.bak" }.join(', ')
    "Missing compose backup in #{scenario_path} (expected one of #{candidates})"
  end

  def dump_expected_fixtures(config, scenario_path)
    # Run the export first so `ensure_defaults!` materializes auto-generated
    # values (admin_password, secret_key_base, postgres password, influx
    # tokens, …) into Configuration.path. Without this step config.yaml would
    # snapshot the pre-defaults state and disagree with the .env/compose.yaml
    # snapshots, which are taken post-export.
    Export::Builder.new(config).write!

    # Preserve root-level key order (grouped logically by the importer) but
    # sort nested keys so diffs stay stable across importer reshuffles.
    data = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
    sorted = data.transform_values { |v| deep_sort_keys(v) }
    config_path = scenario_path.join('helios/config.yaml')
    FileUtils.mkdir_p(config_path.dirname)
    File.write(config_path, Configuration.dump(sorted))

    FileUtils.cp(Compose.path, scenario_path.join('compose.yaml'))
    FileUtils.cp(Env.path, scenario_path.join('.env'))
  end

  def with_scenario_sandbox
    # Export output depends on Rails.env (e.g. Helios service is exported in
    # test but skipped in development), so generate fixtures in the same env
    # that scenarios_spec.rb runs in.
    abort 'Run with RAILS_ENV=test so fixtures match test-env exports.' unless Rails.env.test?

    require 'fileutils'
    require 'tmpdir'

    Dir.mktmpdir do |tmp|
      Rails.configuration.data_path = tmp
      FileUtils.mkdir_p(File.dirname(Configuration.path))
      yield
    end
  end

  def import_scenarios_dir
    Rails.root.join('spec/fixtures/import_scenarios')
  end

  def export_scenarios_dir
    Rails.root.join('spec/fixtures/export_scenarios')
  end

  def scenario_names(dir, pattern)
    Pathname
      .glob(dir.join(pattern))
      .map { |p| p.dirname.parent.relative_path_from(dir).to_s }
      .sort
  end

  desc 'Regenerate config.yaml + compose.yaml + .env for every existing scenario'
  task regenerate: :environment do
    with_scenario_sandbox do
      scenario_names(import_scenarios_dir, '**/helios/config.yaml').each do |name|
        regenerate_scenario(import_scenarios_dir.join(name))
        puts "Regenerated import_scenarios/#{name}/ (config.yaml, compose.yaml, .env)"
      end

      scenario_names(export_scenarios_dir, '*/helios/config.yaml.bak').each do |name|
        regenerate_export_scenario(export_scenarios_dir.join(name))
        puts "Regenerated export_scenarios/#{name}/ (config.yaml, compose.yaml, .env)"
      end
    end
  end

  desc 'Create expected fixtures for a new scenario (usage: fixtures:bootstrap[name])'
  task :bootstrap, [:name] => :environment do |_, args|
    name = args[:name].to_s
    abort "Usage: RAILS_ENV=test bin/rake 'fixtures:bootstrap[name]'" if name.empty?

    with_scenario_sandbox do
      scenario_path = import_scenarios_dir.join(name)
      abort "Scenario '#{name}' not found at #{scenario_path}" unless scenario_path.directory?
      abort missing_compose_backup_message(scenario_path) unless compose_backup_path(scenario_path)

      regenerate_scenario(scenario_path)
      puts "Bootstrapped #{name}/ (config.yaml, compose.yaml, .env)"
    end
  end
end
