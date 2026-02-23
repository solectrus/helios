require 'rails_helper'

describe 'Smoke test', :with_admin do
  before { sign_in }

  it 'loads the dashboard' do
    expect(page).to have_content('SOLECTRUS')
  end
end
