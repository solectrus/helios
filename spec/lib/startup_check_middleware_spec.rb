RSpec.describe StartupCheckMiddleware do
  let(:app) { ->(_env) { [200, { 'content-type' => 'text/html' }, ['OK']] } }
  let(:middleware) { described_class.new(app) }

  def get(path = '/')
    middleware.call(Rack::MockRequest.env_for(path))
  end

  context 'when all checks pass' do
    before do
      allow(StartupCheck).to receive(:run).and_return([])
    end

    it 'passes through to the app' do
      status, _headers, body = get
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end

  context 'when checks fail' do
    let(:failures) do
      [
        StartupCheck::Check.new(name: 'Docker socket', message: 'Not found'),
      ]
    end

    before do
      allow(StartupCheck).to receive(:run).and_return(failures)
    end

    it 'returns 503' do
      status, = get
      expect(status).to eq(503)
    end

    it 'renders an HTML fail screen' do
      _status, headers, body = get
      html = body.first

      expect(headers['content-type']).to eq('text/html; charset=utf-8')
      expect(html).to include('Startup Failed')
      expect(html).to include('Docker socket')
      expect(html).to include('Not found')
    end

    it 'allows the health check endpoint through' do
      status, _headers, body = get('/up')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end

  context 'when checks are run only once' do
    before do
      allow(StartupCheck).to receive(:run).and_return([])
    end

    it 'caches the result' do
      get
      get

      expect(StartupCheck).to have_received(:run).once
    end
  end
end
