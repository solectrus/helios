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
    # Preserve root-level key order (grouped logically by the importer) but
    # sort nested keys so diffs stay stable across importer reshuffles.
    data = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
    sorted = data.transform_values { |v| deep_sort_keys(v) }
    File.write(scenario_path.join('config.yaml'), Configuration.dump(sorted))

    Export::Builder.new(config).write!
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
      yield Rails.root.join('spec/fixtures/import_scenarios')
    end
  end

  desc 'Regenerate config.yaml + compose.yaml + .env for every existing scenario'
  task regenerate: :environment do
    with_scenario_sandbox do |scenarios_dir|
      names = Pathname
              .glob(scenarios_dir.join('**/config.yaml'))
              .map { |p| p.dirname.relative_path_from(scenarios_dir).to_s }
              .sort

      names.each do |name|
        regenerate_scenario(scenarios_dir.join(name))
        puts "Regenerated #{name}/ (config.yaml, compose.yaml, .env)"
      end
    end
  end

  desc 'Create expected fixtures for a new scenario (usage: fixtures:bootstrap[name])'
  task :bootstrap, [:name] => :environment do |_, args|
    name = args[:name].to_s
    abort "Usage: RAILS_ENV=test bin/rake 'fixtures:bootstrap[name]'" if name.empty?

    with_scenario_sandbox do |scenarios_dir|
      scenario_path = scenarios_dir.join(name)
      abort "Scenario '#{name}' not found at #{scenario_path}" unless scenario_path.directory?
      abort missing_compose_backup_message(scenario_path) unless compose_backup_path(scenario_path)

      regenerate_scenario(scenario_path)
      puts "Bootstrapped #{name}/ (config.yaml, compose.yaml, .env)"
    end
  end
end
