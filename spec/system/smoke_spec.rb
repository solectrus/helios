require 'rails_helper'

describe 'Smoke test', :with_admin_password do
  before do
    with_config_yaml
    sign_in
  end

  it 'loads the services page' do
    expect(page).to have_content('SOLECTRUS')
  end
end
