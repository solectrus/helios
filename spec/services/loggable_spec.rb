RSpec.describe Loggable do
  # Capture what reaches Rails.logger. Going through Rails.logger (not a tagged
  # sub-logger) is the whole point — that's what reaches every broadcast sink,
  # including the plain STDOUT logger `rails server` attaches under bin/dev.
  let(:lines) { [] }

  before do
    %i[info warn error debug].each do |level|
      allow(Rails.logger).to receive(level) { |&block| lines << block.call }
    end
  end

  context 'when included (instance context)' do
    let(:klass) do
      Class.new do
        include Loggable

        def self.name = 'Widget'
      end
    end

    it 'prefixes the message with the class name' do
      klass.new.logger.info('hello')
      expect(lines).to include('[Widget] hello')
    end
  end

  context 'when extended (class/module context)' do
    let(:klass) do
      Class.new do
        extend Loggable

        def self.name = 'Gadget'
      end
    end

    it 'prefixes the message with the module name' do
      klass.logger.warn('careful')
      expect(lines).to include('[Gadget] careful')
    end

    it 'forwards every severity through Rails.logger' do
      klass.logger.error('boom')
      expect(Rails.logger).to have_received(:error)
    end
  end
end
