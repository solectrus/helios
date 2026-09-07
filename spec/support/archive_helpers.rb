require 'rubygems/package'

# Builds the tar archives the backup specs hand to the repository adapters,
# the uploader and the restore runner. Every one of them needs the same
# in-memory tar, so it lives here rather than in each spec file.
module ArchiveHelpers
  def tar_archive(entries)
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        entries.each do |name, content|
          tar.add_file_simple(name, 0o644, content.bytesize) { |entry| entry.write(content) }
        end
      end
    end.string
  end

  # A tar carrying nothing but the HELIOS config — enough for every spec that
  # only cares whether the archive could be read at all.
  def config_only_tar(config = "system: {}\n")
    tar_archive('helios/config.yaml' => config)
  end
end

RSpec.configure { |config| config.include ArchiveHelpers }
