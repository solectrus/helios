RSpec.describe DockerStackHelpers do
  # `clear_data_path!` runs rm_rf on whatever a spec's `data_path` names. The
  # fallbacks are dangerous: the test default of `Rails.configuration.data_path`
  # is `spec/fixtures` (every import scenario), the development one is `stack/`
  # (the live local stack). The guard is what keeps a forgotten stub from
  # deleting either.
  subject(:helper) { Class.new { include DockerStackHelpers }.new }

  def disposable(path)
    helper.send(:disposable!, path)
  end

  it 'accepts a path below tmp/' do
    expect(disposable(Rails.root.join('tmp/some-itest').to_s)).to eq(
      Rails.root.join('tmp/some-itest').to_s,
    )
  end

  it 'refuses the fixtures directory (the test-env default)' do
    expect { disposable(Rails.configuration.data_path) }.to raise_error(
      ArgumentError, /only paths below/
    )
  end

  it 'refuses the live stack directory (the development default)' do
    expect { disposable(Rails.root.join('stack').to_s) }.to raise_error(ArgumentError)
  end

  it 'refuses tmp/ itself' do
    expect { disposable(Rails.root.join('tmp').to_s) }.to raise_error(ArgumentError)
  end

  it 'refuses a path that only looks like tmp/' do
    expect { disposable("#{Rails.root.join('tmp')}-evil") }.to raise_error(ArgumentError)
  end

  it 'refuses an escape through ..' do
    expect { disposable(Rails.root.join('tmp/../stack').to_s) }.to raise_error(ArgumentError)
  end

  it 'refuses a blank path' do
    expect { disposable('') }.to raise_error(ArgumentError)
  end
end
