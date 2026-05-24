require 'base64'
require 'json'
require 'open3'
require 'bundler'

namespace :licenses do
  def project_root
    Pathname.new(File.expand_path('../..', __dir__))
  end

  def summary_header
    <<~MD
      # Third-Party Licenses

      HELIOS is distributed under the terms in [LICENSE.md](../../LICENSE.md).
      It bundles or depends on third-party components that remain subject to
      their own licenses. This file is the summary; full per-package notice
      texts for JS runtime dependencies live in
      [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Ruby gem notices ship
      inside each gem directory in the Docker image
      (`/usr/local/bundle/gems/<name>-<version>/{MIT-LICENSE,LICENSE,LICENSE.txt}`)
      and are not duplicated here.

      Regenerate with `bin/rake licenses:generate`.

    MD
  end

  def notices_header
    <<~MD
      # Third-Party Notices

      Full license-notice texts for the JavaScript runtime components compiled
      into the HELIOS Vite bundle. Required by MIT, BSD, OFL-1.1, and CC BY 4.0
      to "include the copyright and permission notice in all copies." Ruby gem
      notices ship inside each gem directory in the Docker image and are not
      duplicated here. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
      for the summary.

      Regenerate with `bin/rake licenses:generate`.

    MD
  end

  # Walks the JS runtime dependency tree by following package.json#dependencies
  # transitively. devDependencies are skipped — only the runtime tree ends up
  # in the Vite bundle that ships in the Docker image.
  def visit_js_dep(name, queue, visited)
    pj_path = project_root.join('node_modules', name, 'package.json')
    return unless pj_path.file?

    info = JSON.parse(pj_path.read)
    visited[name] = dep_info(info)
    (info['dependencies'] || {}).each_key { |d| queue << d unless visited.key?(d) }
  end

  def dep_info(info)
    {
      version: info['version'],
      license: normalize_license(info['license'] || info['licenses']),
      homepage: info['homepage'],
      repository_url: repository_url(info['repository']),
      repository_directory: repository_directory(info['repository']),
    }
  end

  def collect_js_runtime_deps
    pkg = JSON.parse(project_root.join('package.json').read)
    visited = {}
    queue = pkg.fetch('dependencies', {}).keys.dup
    until queue.empty?
      name = queue.shift
      visit_js_dep(name, queue, visited) unless visited.key?(name)
    end
    visited.sort.to_h
  end

  # package.json license fields appear in several historical shapes:
  #   "MIT" | { "type": "MIT" } | [ { "type": "MIT" }, ... ]
  def normalize_license(value)
    case value
    when String then value
    when Hash then value['type'] || value[:type]
    when Array then value.filter_map { |v| normalize_license(v) }.join(', ')
    end
  end

  def repository_url(value)
    case value
    when String then value
    when Hash then value['url']
    end
  end

  def repository_directory(value)
    value['directory'] if value.is_a?(Hash)
  end

  # Locate the bundled LICENSE/COPYING file for a JS package, or nil if the
  # tarball omits it (some upstreams ship one in their git repo but not on npm).
  def read_bundled_notice(name)
    pkg_dir = project_root.join('node_modules', name)
    About::ComponentText::NOTICE_FILENAMES.each do |fn|
      path = pkg_dir.join(fn)
      return path.read if path.file?
    end
    nil
  end

  # Recognised filename patterns for license / notice files in upstream repos.
  def license_file_rx
    /\A(MIT-)?LICEN[CS]E(\.(txt|md))?\z|\ACOPYING(\.(txt|md))?\z/i
  end

  # Parse "git+https://github.com/foo/bar.git" / "https://github.com/foo/bar" /
  # "foo/bar" — the historical shapes that show up in package.json#repository.url.
  # Returns "owner/repo" or nil.
  def parse_github_repo(url)
    return nil unless url

    if (m = url.match(%r{github\.com[/:]([\w.-]+/[\w.-]+?)(?:\.git)?/?\z}))
      m[1]
    elsif url.match?(%r{\A[\w.-]+/[\w.-]+\z})
      url
    end
  end

  # Returns the parsed JSON body or nil on any failure (404, network, gh missing).
  def gh_api(path)
    out, _err, status = Open3.capture3('gh', 'api', path)
    return nil unless status.success?

    JSON.parse(out)
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end

  # Lists files in a repo directory; "" means repo root.
  def gh_list_files(repo, dir)
    path = dir.empty? ? "repos/#{repo}/contents" : "repos/#{repo}/contents/#{dir}"
    entries = gh_api(path)
    return [] unless entries.is_a?(Array)

    entries.filter_map { |e| e['name'] if e['type'] == 'file' }
  end

  def gh_fetch_file(repo, path)
    data = gh_api("repos/#{repo}/contents/#{path}")
    return nil unless data.is_a?(Hash) && data['content']

    # GitHub Contents API returns UTF-8 text, but Base64.decode64 tags the
    # result as ASCII-8BIT. Force-tag so the bytes can be joined with other
    # UTF-8 strings without raising Encoding::CompatibilityError.
    Base64.decode64(data['content']).force_encoding('UTF-8')
  end

  # Search the upstream GitHub repo for a license file and return its raw text.
  # Tries, in order:
  #   1. The `repository.directory` subpath if package.json declares one.
  #   2. A subdirectory matching the unscoped package name (monorepo heuristic
  #      — e.g. @rails/actioncable lives in `rails/rails:/actioncable/`, which
  #      carries a different copyright holder than the repo's root MIT-LICENSE).
  #      Tried before root so the package-local notice wins when both exist.
  #   3. The repo root.
  # Returns nil if no license file is found anywhere. gh resolves repo renames
  # transparently (e.g. surveyjs/surveyjs → surveyjs/survey-library).
  def fetch_upstream_notice(name, info)
    repo = parse_github_repo(info[:repository_url])
    return nil unless repo

    candidates = []
    candidates << info[:repository_directory] if info[:repository_directory]
    candidates << name.split('/').last
    candidates << ''
    candidates.uniq.each do |dir|
      file = gh_list_files(repo, dir).find { |f| f.match?(license_file_rx) }
      next unless file

      path = dir.empty? ? file : "#{dir}/#{file}"
      text = gh_fetch_file(repo, path)
      return text if text
    end
    nil
  end

  # Honest placeholder for the rare case (e.g. stimulus-vite-helpers) where
  # neither the npm tarball nor the upstream repo carries a LICENSE file.
  # Records what package.json declares, links to the source — invents nothing.
  def missing_notice_placeholder(name, info)
    <<~TXT
      No LICENSE file is published with this package's npm tarball, and none
      was found in its upstream repository.

      Package: #{name}
      Declared license (from package.json): #{info[:license] || '(unspecified)'}
      Source: #{info[:repository_url] || info[:homepage] || '(unknown)'}
    TXT
  end

  def render_table(rows)
    lines = ['| Package | License |', '| --- | --- |']
    rows.each { |r| lines << "| `#{r[:name]}` | #{r[:license]} |" }
    lines.join("\n")
  end

  def render_summary(ruby_specs, js_deps)
    ruby_rows = ruby_specs.sort_by(&:name).map do |s|
      { name: s.name, license: Array(s.licenses).join(', ').presence || 'See gem source' }
    end
    js_rows = js_deps.map do |name, info|
      { name: name, license: info[:license].to_s.presence || 'See package source' }
    end
    [
      summary_header,
      "## Ruby Gems\n\n#{render_table(ruby_rows)}\n",
      "## JavaScript Packages\n\n#{render_table(js_rows)}\n",
    ].join("\n")
  end

  def resolve_notice_text(name, info)
    if (text = read_bundled_notice(name))
      puts "  #{name}: bundled LICENSE (#{text.bytesize} bytes)"
      return text
    end
    if (text = fetch_upstream_notice(name, info))
      puts "  #{name}: fetched from upstream repo (#{text.bytesize} bytes)"
      return text
    end
    warn "  #{name}: no LICENSE file found — emitting placeholder"
    missing_notice_placeholder(name, info)
  end

  # Machine-readable header block parsed by About::ComponentText to populate
  # the modal subtitle (version · license) and the homepage link.
  def render_metadata_block(info)
    lines = []
    lines << "- Version: #{info[:version]}" if info[:version].present?
    lines << "- License: #{info[:license]}" if info[:license].present?
    homepage = info[:homepage].presence || info[:repository_url].presence
    lines << "- Homepage: #{homepage}" if homepage
    lines.join("\n")
  end

  def render_notice_section(name, info)
    text = resolve_notice_text(name, info)
    "## #{name}\n\n#{render_metadata_block(info)}\n\n```\n#{text.strip}\n```\n"
  end

  def render_notices(js_deps)
    sections = [notices_header]
    js_deps.each { |name, info| sections << render_notice_section(name, info) }
    sections.join("\n")
  end

  desc 'Generate docs/legal/THIRD_PARTY_LICENSES.md and THIRD_PARTY_NOTICES.md'
  task generate: :environment do
    ruby_specs = Bundler.definition.specs_for(%i[default]).reject { |s| s.name == 'helios' }
    js_deps = collect_js_runtime_deps

    legal_dir = project_root.join('docs/legal')
    legal_dir.mkpath
    summary_path = legal_dir.join('THIRD_PARTY_LICENSES.md')
    notices_path = legal_dir.join('THIRD_PARTY_NOTICES.md')
    summary_path.write(render_summary(ruby_specs, js_deps))
    notices_path.write(render_notices(js_deps))

    # Prettier aligns the Markdown table columns; the raw `| --- |` output is
    # valid but visually unpleasant. Run it inline so the generator output is
    # immediately review-ready and nobody has to remember a follow-up step.
    sh project_root.join('bin/yarn').to_s, 'prettier', '--write',
       '--log-level=warn', summary_path.to_s, notices_path.to_s

    puts "Wrote docs/legal/THIRD_PARTY_LICENSES.md (#{ruby_specs.size} gems, #{js_deps.size} JS pkgs)"
    puts "Wrote docs/legal/THIRD_PARTY_NOTICES.md (#{js_deps.size} JS pkgs)"
  end
end
