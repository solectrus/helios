require 'rails_helper'

RSpec.describe 'Configurations::Chapters', :with_admin do
  let(:configuration) { Configuration.current }

  before { login }

  describe 'GET /configuration/chapters/:id (show)' do
    it 'returns JSON for a valid chapter' do
      get configuration_chapter_path(id: 'devices')

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/json')

      json = response.parsed_body
      expect(json).to be_a(Hash)
    end

    it 'returns 404 for non-existent chapter' do
      get configuration_chapter_path(id: 'nonexistent')

      expect(response).to redirect_to(configuration_path)
    end

    Chapter::NAMES.each do |chapter_name|
      it "returns JSON for #{chapter_name} chapter" do
        get configuration_chapter_path(id: chapter_name)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
      end
    end
  end

  describe 'GET /configuration/chapters/:id/edit' do
    it 'renders the chapter form' do
      get edit_configuration_chapter_path(id: 'devices')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('devices')
    end

    it 'redirects for invalid chapter' do
      get edit_configuration_chapter_path(id: 'invalid')

      expect(response).to redirect_to(configuration_path)
    end
  end

  describe 'PATCH /configuration/chapters/:id' do
    it 'updates the chapter data' do
      chapter_data = { 'field1' => 'value1', 'field2' => 'value2' }

      patch configuration_chapter_path(id: 'devices'),
            params: { chapter: chapter_data.to_json }

      expect(response).to redirect_to(configuration_path)
      expect(configuration.reload.chapter('devices')).to eq(chapter_data)
    end

    it 'redirects for invalid chapter' do
      patch configuration_chapter_path(id: 'invalid'),
            params: { chapter: { foo: 'bar' }.to_json }

      expect(response).to redirect_to(configuration_path)
    end
  end
end
