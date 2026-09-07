RSpec.describe UserPreferences do
  def preferences(cookie)
    described_class.new({ described_class::COOKIE_NAME => cookie })
  end

  it 'reads the stored preferences' do
    prefs = preferences({ 'hide_unused' => true, 'locale' => 'de' }.to_json)

    expect(prefs.hide_unused?).to be(true)
    expect(prefs.locale).to eq('de')
  end

  it 'falls back to the defaults without a cookie' do
    prefs = described_class.new({})

    expect(prefs.hide_unused?).to be(false)
    expect(prefs.locale).to be_nil
  end

  # A cookie is user-supplied data: a broken one must read as "no preferences",
  # never take a page down.
  it 'ignores a cookie that is not JSON' do
    prefs = preferences('not json')

    expect(prefs.hide_unused?).to be(false)
  end

  describe '#resolved_locale' do
    it 'prefers the stored locale' do
      expect(preferences({ 'locale' => 'de' }.to_json).resolved_locale('en')).to eq(:de)
    end

    it 'falls back to the browser language' do
      expect(described_class.new({}).resolved_locale('de-DE,de;q=0.9')).to eq(:de)
    end

    it 'falls back to the default locale for a language HELIOS does not ship' do
      expect(described_class.new({}).resolved_locale('fr-FR')).to eq(I18n.default_locale)
    end
  end
end
