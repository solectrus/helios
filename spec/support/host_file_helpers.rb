# The support bundle and the host stats read files under /proc, /sys and /etc
# that exist on the user's Linux host but not on a macOS development machine.
# Stubbing the access keeps every such spec answering the same everywhere.
module HostFileHelpers
  # Pass `lines:` for a line-by-line read, `content:` for a whole-file read,
  # or `error:` for a file that is there but cannot be read.
  def stub_host_file(path, lines: nil, content: nil, error: nil)
    stub_real_file_access
    allow(File).to receive(:exist?).with(path).and_return(true)

    allow(File).to receive(:read).with(path).and_return(content) if content
    allow(File).to receive(:foreach).with(path) { |&block| lines.each(&block) } if lines
    stub_unreadable_file(path, error) if error
  end

  def stub_missing_host_file(path)
    stub_real_file_access
    allow(File).to receive(:exist?).with(path).and_return(false)
  end

  private

  def stub_real_file_access
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:foreach).and_call_original
  end

  def stub_unreadable_file(path, error)
    allow(File).to receive(:read).with(path).and_raise(error)
    allow(File).to receive(:foreach).with(path).and_raise(error)
  end
end

RSpec.configure { |config| config.include HostFileHelpers }
