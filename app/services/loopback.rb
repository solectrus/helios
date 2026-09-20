# Addresses that only ever reach whoever asks. They serve two callers: a
# connection test, where a collector in its own container reaches that
# container instead of the device meant, and the adoption of app_host, where
# such an address would name the machine to nobody but itself.
#
# `*.localhost` belongs to the group because it resolves to the loopback
# interface of the asking host (RFC 6761), and the whole 127.0.0.0/8 range is
# loopback, not just 127.0.0.1.
class Loopback
  NAMES = %w[localhost ::1 0.0.0.0].freeze
  IPV4 = /\A127\./

  # The rule of .host? as a pattern a survey validates against: an address
  # that is none of these. Written out instead of derived from the constants
  # above, because a JavaScript regex takes neither \A nor Ruby's escaping.
  # The field sees what was typed, so the pattern also skips what #host?
  # strips before it judges: the space around the address and the brackets of
  # an IPv6 address. A spec holds the two to the same answers.
  SURVEY_PATTERN = '^(?!\s*\[?(?:localhost|::1|0\.0\.0\.0|127\..*|.*\.localhost)\]?\s*$).+$'.freeze

  def self.host?(host)
    normalized = host.to_s.strip.downcase.delete_prefix('[').delete_suffix(']')
    return false if normalized.blank?

    NAMES.include?(normalized) || normalized.end_with?('.localhost') || normalized.match?(IPV4)
  end
end
