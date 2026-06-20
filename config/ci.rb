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
  step 'Test: RSpec', 'bin/turbo_tests'
  step 'Test: Coverage', 'bin/coverage'
end
