# Run using bin/ci

CI.run do
  step 'Setup', 'bin/setup --skip-server'

  step 'Style: Ruby', 'bin/rubocop'
  step 'Style: ERB', 'bin/yarn erb:check'
  step 'Style: JavaScript', 'bin/yarn lint'
  step 'Style: TypeScript', 'bin/yarn tsc'
  step 'Style: Shell', "shellcheck $(git ls-files '*.sh')"

  step 'Lint: ERB', 'bin/herb lint'
  step 'Validate: ERB', 'bin/herb analyze .'

  step 'Security: Gem audit', 'bin/bundler-audit'
  step 'Security: Brakeman code analysis',
       'bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error'

  step 'Build: Vite assets', 'yarn vite build --mode test'

  step 'Test: Bats', 'bats --recursive spec/bats/'
  step 'Test: RSpec', 'bin/rspec'
end
