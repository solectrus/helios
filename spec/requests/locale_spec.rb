RSpec.describe 'Locale', :with_admin_password do
  before { with_config_yaml }

  def lang_attr
    response.body[/<html lang="([^"]+)"/, 1]
  end

  describe 'GET /session/new' do
    it 'uses default locale when no preference or header is set' do
      get new_session_path
      expect(lang_attr).to eq('en')
    end

    it 'detects locale from Accept-Language header' do
      get new_session_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }
      expect(lang_attr).to eq('de')
    end

    it 'falls back to default for unsupported Accept-Language' do
      get new_session_path, headers: { 'Accept-Language' => 'fr,es;q=0.8' }
      expect(lang_attr).to eq('en')
    end

    it 'prefers explicit cookie preference over Accept-Language' do
      cookies[:preferences] = { locale: 'en' }.to_json
      get new_session_path, headers: { 'Accept-Language' => 'de' }
      expect(lang_attr).to eq('en')
    end
  end
end
