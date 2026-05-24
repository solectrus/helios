class AboutController < ApplicationController
  LEGAL_DIR = Rails.root.join('docs/legal')

  def show
    @license = strip_license_preamble(read_localized_license)
    @components = helpers.parse_components(LEGAL_DIR.join('THIRD_PARTY_LICENSES.md').read)
    @git = Rails.configuration.x.git
    @commit_time = Time.zone.parse(@git.commit_time) if @git.commit_time.present?
  end

  private

  def read_localized_license
    localized = LEGAL_DIR.join("LICENSE.#{I18n.locale}.md")
    (localized.exist? ? localized : Rails.root.join('LICENSE.md')).read
  end

  # The hero already shows the copyright line, so strip the leading "# License"
  # + "Copyright …" preamble before rendering to avoid duplicating it.
  def strip_license_preamble(text)
    text.sub(/\A(?:#\s+[^\n]*\n+)?Copyright[^\n]*\n+/, '')
  end
end
