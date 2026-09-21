# A host address a user handed to HELIOS: the address other devices reach
# SOLECTRUS at, the address of a device a collector polls, the target of a
# connection test.
#
# Nobody types such an address, they paste what something else showed them. It
# therefore arrives with a scheme in front, a port or a path behind, brackets
# around an IPv6 address, upper case, and space around all of it. `.normalize`
# drops every one of those and leaves the host alone. That form is what the
# configuration stores, so a reader can put the value into a URL or into a
# host rule without parsing it a second time.
#
# `.loopback?` answers the one question that makes an address unusable: whether
# it reaches nobody but whoever asks. A collector in its own service reaches
# that service at such an address instead of the device meant, and SOLECTRUS
# reached at one names the machine to itself alone.
class HostAddress
  # `*.localhost` belongs to the group because it resolves to the loopback
  # interface of the asking host (RFC 6761), and the whole 127.0.0.0/8 range is
  # loopback, not just 127.0.0.1.
  #
  # One source for the rule: `.loopback?` compiles it here, and the form that
  # asks for an address compiles it again in the browser (see SURVEY_PATTERN).
  # Written out twice, the two drifted apart. The syntax is therefore the part
  # Ruby and JavaScript share: no \A, no \z, no Ruby escaping.
  #
  # Split by whether the address carries colons of its own, because that decides
  # whether a port may follow it: `localhost:3000` is localhost on a port, while
  # `::1:3000` is an address in its own right and not `::1` on a port. Bracketed,
  # both take a port, which is what the brackets are for.
  LOOPBACK_NAMED = '(?:localhost|[^\s/]*\.localhost|127\.[^\s/]*|0\.0\.0\.0)'.freeze
  LOOPBACK_V6 = '::1'.freeze
  LOOPBACK = "(?:#{LOOPBACK_NAMED}|#{LOOPBACK_V6})".freeze

  # The scheme of a pasted URL. Dropped rather than refused, because a user who
  # copies the address bar copies it along. Shared with the browser for the
  # same reason as LOOPBACK.
  SCHEME = '(?:[a-z][a-z0-9+.\-]*://)?'.freeze

  # An IPv6 address in brackets, with or without a port. The brackets exist to
  # tell the colons of the address from the one before the port.
  BRACKETED = /\A\[(?<host>[^\]]*)\](?::\d+)?\z/

  # A name or an IPv4 address with a port. One colon only, so a bare IPv6
  # address keeps all of its own.
  PORTED = /\A(?<host>[^:]+):\d+\z/

  SCHEME_MATCHER = /\A#{SCHEME}/
  LOOPBACK_MATCHER = /\A#{LOOPBACK}\z/

  # The same rule for the browser, wrapped in what the field still carries at
  # the moment it is typed: an address `.normalize` has not seen yet. So the
  # wrapper skips the space around it, the scheme, the brackets, the port and
  # the path, and the rule inside judges what is left. A spec holds the wrapper
  # to the same answers as `.normalize`.
  SURVEY_PATTERN = "^(?!\\s*#{SCHEME}(?:\\[#{LOOPBACK}\\](?::\\d+)?" \
                   "|#{LOOPBACK_NAMED}(?::\\d+)?|#{LOOPBACK_V6})(?:/.*)?\\s*$).+$".freeze

  # The host alone, or nil when nothing is left of the value.
  def self.normalize(value)
    host = value.to_s.strip.downcase.sub(SCHEME_MATCHER, '')
    host = host.split('/', 2).first.to_s

    strip_port(host).presence
  end

  def self.loopback?(value)
    host = normalize(value)

    host.present? && host.match?(LOOPBACK_MATCHER)
  end

  # The host alone, but only where it names the machine to others: the two
  # questions above asked as one. Callers that store an address someone else
  # has to reach ask it this way, because such an address is either usable or
  # not there at all.
  def self.public_host(value)
    host = normalize(value)

    host unless host.nil? || loopback?(host)
  end

  # The host as a URL takes it. An address that carries colons of its own needs
  # brackets there, so that a reader can tell those colons from the one in
  # front of a port.
  def self.for_url(host)
    host.to_s.include?(':') ? "[#{host}]" : host.to_s
  end

  def self.strip_port(host)
    match = BRACKETED.match(host) || PORTED.match(host)

    match ? match[:host] : host
  end
  private_class_method :strip_port
end
