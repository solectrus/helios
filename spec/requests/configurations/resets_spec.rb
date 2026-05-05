RSpec.describe 'Configurations::Resets', :with_admin_password do
  let(:dir) { with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' }) }
  let(:compose_path) { File.join(dir, 'compose.yaml') }
  let(:env_path) { File.join(dir, '.env') }
  let(:compose_backup) { StackBackup.backup_path(compose_path) }
  let(:env_backup) { StackBackup.backup_path(env_path) }

  before do
    dir
    login
  end

  describe 'POST /configuration/reset' do
    context 'when backup files are present' do
      before do
        File.write(compose_path, "services:\n  dashboard:\n    image: edited:latest\n")
        File.write(env_path, "TZ=UTC\n")
        File.write(compose_backup, "services:\n  dashboard:\n    image: original:latest\n")
        File.write(env_backup, "TZ=Europe/Berlin\n")

        allow(StackReset).to receive(:perform!)
      end

      it 'calls StackReset.perform! and redirects to the configuration page' do
        post configuration_reset_path

        expect(StackReset).to have_received(:perform!)
        expect(response).to redirect_to(sensors_path)
        expect(flash[:notice]).to be_present
      end
    end

    context 'when backup files are missing' do
      it 'does not call StackReset.perform!' do
        allow(StackReset).to receive(:perform!)

        post configuration_reset_path

        expect(StackReset).not_to have_received(:perform!)
        expect(response).to redirect_to(sensors_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'DELETE /configuration/reset' do
    context 'when backup files are present' do
      before do
        File.write(compose_backup, "services:\n  dashboard:\n    image: original:latest\n")
        File.write(env_backup, "TZ=Europe/Berlin\n")
      end

      it 'deletes backup files and redirects' do
        delete configuration_reset_path

        expect(File.exist?(compose_backup)).to be false
        expect(File.exist?(env_backup)).to be false
        expect(response).to redirect_to(sensors_path)
        expect(flash[:notice]).to be_present
      end
    end

    context 'when backup files are missing' do
      it 'redirects with an alert' do
        delete configuration_reset_path

        expect(response).to redirect_to(sensors_path)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
