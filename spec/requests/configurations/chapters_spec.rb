RSpec.describe 'Configurations::Chapters', :with_admin do
  let(:configuration) { Configuration.current }

  before { login }

  describe 'GET /configuration/chapters/new' do
    it 'renders the survey form for a valid device kind' do
      get new_configuration_chapter_path(kind: 'inverter')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects for invalid kind' do
      get new_configuration_chapter_path(kind: 'nonexistent')

      expect(response).to redirect_to(configuration_path)
    end
  end

  describe 'POST /configuration/chapters' do
    it 'creates a device chapter with name from survey data' do
      chapter_data = {
        'name' => 'Dach Süd',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      }

      expect do
        post configuration_chapters_path,
             params: { kind: 'inverter', chapter: chapter_data.to_json }
      end.to change(Chapter, :count).by(1)

      chapter = Chapter.last
      expect(chapter.kind).to eq('inverter')
      expect(chapter.name).to eq('Dach Süd')
      expect(chapter.data).to eq(
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      )
      expect(response).to redirect_to(configuration_path)
    end

    it 'creates a singleton chapter with kind as name' do
      expect do
        post configuration_chapters_path,
             params: { kind: 'system' }
      end.to change(Chapter, :count).by(1)

      chapter = Chapter.last
      expect(chapter.kind).to eq('system')
      expect(chapter.name).to eq('system')
      expect(response).to redirect_to(edit_configuration_chapter_path(chapter))
    end
  end

  describe 'GET /configuration/chapters/:id/edit' do
    it 'renders the survey form for an existing chapter' do
      chapter = configuration.chapters.create!(
        kind: 'inverter', name: 'Dach Süd', data: {},
      )

      get edit_configuration_chapter_path(chapter)

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for non-existent chapter' do
      get edit_configuration_chapter_path(id: 999_999)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /configuration/chapters/:id' do
    it 'updates a device chapter including name' do
      chapter = configuration.chapters.create!(
        kind: 'inverter', name: 'Dach Süd', data: {},
      )
      chapter_data = {
        'name' => 'Dach Nord',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      }

      patch configuration_chapter_path(chapter),
            params: { chapter: chapter_data.to_json }

      expect(response).to redirect_to(configuration_path)
      chapter.reload
      expect(chapter.name).to eq('Dach Nord')
      expect(chapter.data).to eq(
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      )
    end

    it 'updates a singleton chapter without changing name' do
      chapter = configuration.chapters.create!(
        kind: 'system', name: 'system', data: {},
      )
      chapter_data = { 'app_host' => 'example.com' }

      patch configuration_chapter_path(chapter),
            params: { chapter: chapter_data.to_json }

      expect(response).to redirect_to(configuration_path)
      chapter.reload
      expect(chapter.name).to eq('system')
      expect(chapter.data).to eq('app_host' => 'example.com')
    end
  end

  describe 'DELETE /configuration/chapters/:id' do
    it 'deletes the chapter' do
      chapter = configuration.chapters.create!(
        kind: 'inverter', name: 'Dach Süd', data: {},
      )

      expect do
        delete configuration_chapter_path(chapter)
      end.to change(Chapter, :count).by(-1)

      expect(response).to redirect_to(configuration_path)
    end
  end
end
