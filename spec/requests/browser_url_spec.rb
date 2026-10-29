# The SOLECTRUS dashboard links to the URL HELIOS was opened at last
RSpec.describe BrowserUrl, :with_admin_password do
  before { with_config_yaml }

  def reported_url
    get '/up'
    response.headers['X-Browser-Url']
  end

  it 'reports the URL of a signed-in request' do
    host! '192.168.1.10:3999'
    login
    get sensors_path

    expect(reported_url).to eq('http://192.168.1.10:3999')
  end

  # The login page renders for anybody
  it 'ignores a request without a sign-in' do
    host! '192.168.1.10:3999'
    get new_session_path

    expect(reported_url).to be_nil
  end

  it 'ignores a loopback address' do
    host! 'localhost:3999'
    login
    get sensors_path

    expect(reported_url).to be_nil
  end

  it 'reports the URL opened last' do
    host! '192.168.1.10:3999'
    login
    # The session cookie belongs to the host
    host! 'helios.example.com:3999'
    login

    expect(reported_url).to eq('http://helios.example.com:3999')
  end

  # The data dir outlives a restart of HELIOS
  it 'keeps the URL in the data dir' do
    host! '192.168.1.10:3999'
    login

    expect(File.read(File.join(Rails.configuration.data_path, 'helios', 'browser_url')))
      .to eq('http://192.168.1.10:3999')
  end
end
