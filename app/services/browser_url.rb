# The URL the browser opened HELIOS at last, like http://192.168.1.10:3999.
# HELIOS reports it on /up (see HealthController), so the menu of the SOLECTRUS
# dashboard links there. The dashboard cannot know it by itself: behind a
# reverse proxy it sees only its domain, where the port of HELIOS is often
# closed.
#
# Only a signed-in request counts, so nobody else chooses where the link of
# the dashboard leads. A loopback address names the machine to itself alone,
# so it does not count either.
#
# Lives in HELIOS's data dir next to the other runtime state, so it survives a
# restart. The file changes only when the URL does.
class BrowserUrl
  FILENAME = 'browser_url'.freeze
  private_constant :FILENAME

  def self.remember(request)
    return if HostAddress.loopback?(request.host)

    url = request.base_url
    return if url == current

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, url)
  end

  def self.current
    File.read(path).presence if File.exist?(path)
  end

  def self.path
    File.join(Rails.configuration.data_path, 'helios', FILENAME)
  end
  private_class_method :path
end
