# Normalizes content HELIOS reads from disk (or from a child process) to plain
# UTF-8: decodes UTF-16, repairs Latin-1/CP1252 bytes and drops a leading byte
# order mark.
#
# Users edit `.env` with whatever editor their NAS or desktop ships, and many
# of those still default to Latin-1/CP1252. A single umlaut in a comment is
# then enough to make every String operation on the file raise
# (Encoding::CompatibilityError / ArgumentError: invalid byte sequence in
# UTF-8), which took down the whole start page. Normalizing at the read
# boundary keeps the rest of the code free of encoding checks; writing the
# file back repairs it permanently.
#
# compose.yaml deliberately gets no such treatment: docker itself refuses to
# parse non-UTF-8 YAML, so that stack cannot work either way.
module TextEncoding
  module_function

  # The marks a UTF-16 file starts with (little and big endian). Only the mark
  # reveals that a file is not single-byte at all; its remaining bytes look
  # like ordinary Latin-1 garbage to the repair below, which would turn the
  # whole file into mojibake and then parse zero variables out of it.
  UTF_16_BOMS = ["\xFF\xFE".b, "\xFE\xFF".b].freeze

  def utf8(content)
    bytes = content.to_s.b
    string = utf16(bytes) || bytes.force_encoding(Encoding::UTF_8)

    # The mark itself is valid UTF-8, but poison for anything that parses the
    # first line: editors offer "UTF-8 with BOM" (Synology's does) and docker
    # compose drops it silently, so HELIOS has to as well. Dropped before the
    # repair below, which would turn the mark into "ï»¿".
    string = string.delete_prefix("\uFEFF")
    return string if string.valid_encoding?

    repair(string)
  end

  # Repairs the invalid byte sequences one at a time and leaves everything that
  # is already valid untouched. Hand-edited files are regularly mixed, e.g. a
  # Latin-1 umlaut in a comment next to a UTF-8 umlaut in a password: with the
  # whole file transcoded at once, "Grün" would become "GrÃ¼n" and #save would
  # persist that, leaving the services with a password their data volume does
  # not know.
  def repair(string)
    string.scrub { |invalid| transcode(invalid, Encoding::WINDOWS_1252) || transcode(invalid, Encoding::ISO_8859_1) }
  end

  # CP1252 first (superset of Latin-1 in the printable range, so it also
  # recovers curly quotes and dashes from Windows editors), then Latin-1,
  # which maps all 256 byte values and therefore always succeeds.
  def transcode(string, from)
    string.encode(Encoding::UTF_8, from)
  rescue EncodingError
    nil
  end

  # Ruby's UTF-16 reads the endianness off the mark and consumes it. Replacing
  # what a truncated file cuts in half costs a single character, while falling
  # through to the single-byte repair would cost the whole file.
  def utf16(bytes)
    return unless UTF_16_BOMS.include?(bytes.byteslice(0, 2))

    bytes.encode(Encoding::UTF_8, Encoding::UTF_16, invalid: :replace, undef: :replace)
  rescue EncodingError
    nil
  end
end
