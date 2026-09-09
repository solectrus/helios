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

  def self.host?(host)
    normalized = host.to_s.strip.downcase.delete_prefix('[').delete_suffix(']')
    return false if normalized.blank?

    NAMES.include?(normalized) || normalized.end_with?('.localhost') || normalized.match?(IPV4)
  end
end
