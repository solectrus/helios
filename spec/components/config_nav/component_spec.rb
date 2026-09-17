RSpec.describe ConfigNav::Component, type: :component do
  let(:dir) { config_yaml_dir }

  describe 'the warning sign' do
    # A sensor reads through SENEC, which names no host yet. The data sources
    # are the only entry that can carry a sign: what the Settings screen holds
    # is either defaulted or asked for before any screen opens (see
    # CommissioningController).
    before { with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } }) }

    def signs(rendered)
      rendered
        .css('a')
        .select { |a| a.css('i.fa-triangle-exclamation').any? }
        .to_h { |a| [a['href'], a.css('i.fa-triangle-exclamation').attr('class').value] }
    end

    it 'marks the entry that carries an open setting' do
      rendered = render_inline(described_class.new(active_tab: :sensors))

      expect(signs(rendered).transform_values { |css| css.include?('text-warning') })
        .to eq({ '/datasources' => true })
    end

    it 'holds the sign back on the entry that is already open' do
      rendered = render_inline(described_class.new(active_tab: :datasources))

      expect(signs(rendered)['/datasources']).to include(Header::Component::MUTED_WARNING_CLASSES)
    end

    # The sign is an icon, and its tooltip lives in an attribute a screen
    # reader does not read. So the entry carries the words as well (the top
    # navigation and the dock do the same).
    it 'names what it marks, for a screen reader' do
      rendered = render_inline(described_class.new(active_tab: :sensors))

      expect(rendered.css('a .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end
  end

  describe 'the reset block' do
    it 'is hidden while no backup exists' do
      rendered = render_inline(described_class.new)

      expect(rendered).to have_no_text('Reset')
    end

    context 'with a backup of the imported stack' do
      before do
        File.write(File.join(dir, 'compose.yaml'), "services: {}\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
        StackBackup.create!
      end

      it 'offers every reset dialog the dialogs component defines' do
        rendered = render_inline(described_class.new)

        buttons = rendered.css('button[data-action="modal-opener#open"]')
        expect(buttons.pluck('data-modal-opener-id-param'))
          .to eq(ResetDialogs::Component::DIALOGS.pluck(:id))
      end

      # `only: :tabs` renders the navigation without the file and reset block.
      it 'is left out when only the tabs are requested' do
        rendered = render_inline(described_class.new(only: :tabs))

        expect(rendered.css('button[data-action="modal-opener#open"]')).to be_empty
      end
    end
  end

  # The file is for a proxy that routes published host ports, so it is offered
  # only there. On a shared network the routers are labels on the services
  # themselves, and a file to copy would be a second set of routers for them.
  describe 'the generated Traefik file' do
    # The file list needs a finished setup, which a configured sensor stands for.
    def offered_with?(reverse_proxy)
      with_config_yaml(
        'system' => { 'app_host' => 'solar.example.com' },
        'reverse_proxy' => reverse_proxy,
        'sensors' => { 'inverter_power' => { 'source' => 'external' } },
      )

      render_inline(described_class.new(active_tab: :settings)).css('a[href="/services/files/traefik"]').any?
    end

    it 'is offered where the proxy routes host ports' do
      expect(offered_with?({ 'mode' => 'external', 'bind_ip' => '10.0.0.5' })).to be true
    end

    it 'is not offered on a shared network' do
      expect(offered_with?({ 'mode' => 'external', 'proxy_network' => 'edge' })).to be false
    end

    it 'is not offered without an external proxy' do
      expect(offered_with?({})).to be false
    end
  end
end
