module About
  # Resolves the full license text + metadata for a single bundled component.
  class ComponentText
    NOTICE_FILENAMES = %w[MIT-LICENSE LICENSE LICENSE.txt LICENSE.md LICENCE LICENCE.txt COPYING COPYING.txt].freeze
    JS_META_KEYS = { 'Version' => :version, 'License' => :license, 'Homepage' => :homepage }.freeze
    META_LINE_RX = /^- (Version|License|Homepage):\s*(.+)$/

    def self.for(category:, name:)
      new(category, name).call
    end

    def initialize(category, name)
      @category = category
      @name = name
    end

    def call
      case @category
      when 'gem' then gem_payload
      when 'js' then js_payload
      end
    end

    private

    attr_reader :name

    def gem_payload
      spec = Bundler.definition.specs_for(%i[default]).find { |s| s.name == name }
      return nil unless spec

      {
        heading: spec.name,
        subtitle: "#{spec.version} · #{Array(spec.licenses).join(', ').presence || 'license not declared'}",
        text: read_gem_license(spec),
        url: spec.homepage,
      }
    end

    def read_gem_license(spec)
      NOTICE_FILENAMES.each do |fn|
        path = File.join(spec.full_gem_path, fn)
        return File.read(path) if File.file?(path)
      end
      "No LICENSE file ships inside the #{spec.name} gem. " \
        "Consult the upstream project at #{spec.homepage} for the full license text."
    end

    def js_payload
      match = notices_markdown.match(/^## #{Regexp.escape(name)}\s*\n(.*?)(?=^## |\z)/m)
      return nil unless match

      section = match[1]
      meta = parse_js_metadata(section)
      body = section.gsub(META_LINE_RX, '').strip.gsub(/^```\s*$\n?/, '').strip

      {
        heading: name,
        subtitle: js_subtitle(meta),
        text: body,
        url: meta[:homepage],
      }
    end

    def parse_js_metadata(section)
      section.scan(META_LINE_RX).each_with_object({}) do |(key, value), meta|
        meta[JS_META_KEYS.fetch(key)] = value.strip
      end
    end

    def js_subtitle(meta)
      return nil if meta.empty?

      [meta[:version], meta[:license].presence || 'license not declared'].compact_blank.join(' · ')
    end

    def notices_markdown
      Rails.root.join('docs/legal/THIRD_PARTY_NOTICES.md').read
    end
  end
end
