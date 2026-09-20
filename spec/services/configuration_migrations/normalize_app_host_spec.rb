RSpec.describe ConfigurationMigrations::NormalizeAppHost do
  subject(:up) { described_class.new.up(data) }

  def data_with(app_host)
    { 'system' => { 'app_host' => app_host, 'timezone' => 'Europe/Berlin' } }
  end

  # An earlier HELIOS took the field as typed, so it holds whatever the user
  # pasted out of the browser.
  {
    'http://solar.example.com/' => 'solar.example.com',
    'solar.example.com:3000' => 'solar.example.com',
    '192.168.1.10:8086' => '192.168.1.10',
    '  Solar.Example.COM  ' => 'solar.example.com',
  }.each do |stored, host|
    context "with the stored address #{stored.inspect}" do
      let(:data) { data_with(stored) }

      it "leaves #{host.inspect}" do
        expect(up['system']['app_host']).to eq(host)
      end
    end
  end

  # The old form prefilled the field from the browser's address bar without a
  # check, so whoever set HELIOS up at one of these stored it.
  ['localhost', 'LOCALHOST', 'helios.localhost', '127.0.0.1', '127.1.2.3', '::1', '0.0.0.0',
   'http://localhost:3000/', ''].each do |host|
    context "with the stored address #{host.inspect}" do
      let(:data) { data_with(host) }

      it 'drops the address and keeps the rest of the section' do
        expect(up['system']).to eq('timezone' => 'Europe/Berlin')
      end
    end
  end

  context 'with an address that already names the machine to others' do
    let(:data) { data_with('solar.example.com') }

    it 'keeps it' do
      expect(up['system']['app_host']).to eq('solar.example.com')
    end
  end

  context 'with no address at all' do
    let(:data) { { 'system' => { 'timezone' => 'Europe/Berlin' } } }

    it 'leaves the section alone' do
      expect(up['system']).to eq('timezone' => 'Europe/Berlin')
    end
  end

  # A migration must never keep the app from booting, so an unexpected shape
  # passes through untouched.
  context 'without a system section' do
    let(:data) { { 'deployment' => { 'mode' => 'full' } } }

    it 'passes the data through' do
      expect(up).to eq('deployment' => { 'mode' => 'full' })
    end
  end
end
