RSpec.describe 'GeneratedFiles', :with_admin do
  let(:tmp_dir) { Rails.root.join('tmp/test_stack') }

  before do
    FileUtils.mkdir_p(tmp_dir)
    allow(Rails.configuration).to receive(:helios_stack_path).and_return(
      tmp_dir.to_s,
    )
    login
  end

  after { FileUtils.rm_rf(tmp_dir) }

  describe 'GET /generated_files' do
    context 'with expert mode enabled' do
      before { cookies[:expert_mode] = 'true' }

      it 'renders the generated files page' do
        get generated_files_path

        expect(response).to have_http_status(:ok)
      end

      it 'displays compose.yaml content' do
        get generated_files_path

        expect(response.body).to include('compose.yaml')
        expect(response.body).to include('solectrus')
      end

      it 'displays .env content' do
        get generated_files_path

        expect(response.body).to include('.env')
      end
    end

    context 'without expert mode' do
      it 'redirects to root' do
        get generated_files_path

        expect(response).to redirect_to(root_path)
      end
    end
  end
end
