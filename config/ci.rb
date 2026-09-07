# Run using bin/ci

CI.run do
  step 'Setup', 'bin/setup --skip-server'

  step 'Style: Ruby', 'bin/rubocop'
  step 'Style: ERB', 'bun run erb:check'
  step 'Style: JavaScript', 'bun run lint'
  step 'Style: TypeScript', 'bun run tsc'
  step 'Style: Shell', "shellcheck $(git ls-files '*.sh')"

  step 'Lint: ERB', 'bin/herb lint'
  step 'Validate: ERB', 'bin/herb analyze .'

  step 'Security: Gem audit', 'bin/bundler-audit'
  step 'Security: Brakeman code analysis',
       'bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error'

  step 'Build: Vite assets', 'bunx vite build --mode test'

  step 'Test: Bats', 'bats --recursive spec/bats/'

  # Mirrors .github/workflows/ci.yml, where the two RSpec runs are separate
  # jobs. The coverage gate must see the fast suite alone, exactly as the
  # `rspec` job does. If it saw the integration specs too, code covered only
  # by them would pass here and fail on GitHub.
  step 'Test: RSpec', "bin/turbo_tests -t '~integration'"
  step 'Test: Coverage', 'bin/coverage'
  # The slowest step by far, and it needs a Docker daemon. `SKIP_INTEGRATION=1
  # bin/ci` leaves it out for a quick loop. NO_COVERAGE keeps the report of
  # the fast suite intact, because this run must not count towards the gate.
  unless ENV['SKIP_INTEGRATION']
    step 'Test: RSpec (integration)',
         'NO_COVERAGE=1 bin/turbo_tests -t integration spec/integration'
  end
end
