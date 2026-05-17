RSpec.describe Export::Services::PostgresqlBackup do
  subject(:service) { described_class.new(configuration) }

  describe '#to_h' do
    let(:configuration) { Configuration.from_data('postgresql' => { 'image' => postgresql_image }) }

    context 'when PostgreSQL runs major version 18' do
      let(:postgresql_image) { 'postgres:18-alpine' }

      it 'tags the backup image to match' do
        expect(service.to_h[:image]).to eq('ghcr.io/solectrus/postgres-s3-backup:18')
      end
    end

    context 'when PostgreSQL runs an older major version' do
      let(:postgresql_image) { 'postgres:17-alpine' }

      it 'tracks the PostgreSQL major version' do
        expect(service.to_h[:image]).to eq('ghcr.io/solectrus/postgres-s3-backup:17')
      end
    end

    context 'when the PostgreSQL image has no recognizable major version' do
      let(:postgresql_image) { 'mycustom/postgres' }

      it 'falls back to the registry default' do
        expect(service.to_h[:image]).to eq(DockerImages.current(:POSTGRESQL_BACKUP))
      end
    end
  end
end
