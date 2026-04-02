require 'rails_helper'

RSpec.describe ApplicationCable::Connection do
  context 'without admin password', :without_admin_password do
    before { with_config_yaml }

    it 'accepts the connection' do
      connect '/cable'

      expect(connection).to be_present
    end
  end

  context 'with admin password', :with_admin_password do
    before { with_config_yaml }

    it 'rejects unauthenticated connections' do
      expect do
        connect '/cable'
      end.to have_rejected_connection
    end

    it 'accepts authenticated connections' do
      connect '/cable', session: { authenticated: true }

      expect(connection).to be_present
    end
  end
end
