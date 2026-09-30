RSpec.describe 'Health' do
  describe 'GET /up' do
    it 'responds successfully' do
      get '/up'
      expect(response).to have_http_status(:ok)
    end

    it 'sets the X-Boot-Id header' do
      get '/up'
      expect(response.headers['X-Boot-Id']).to eq(
        Rails.application.config.boot_id,
      )
    end

    it 'sets the X-Version header' do
      get '/up'
      expect(response.headers['X-Version']).to eq(
        Rails.application.config.x.git.commit_version,
      )
    end

    describe 'X-Action-Required header' do
      before { with_startable_config_yaml }

      it 'is absent while the stack runs as configured' do
        allow(Orchestration::StackStatus).to receive(:overall).and_return(:ok)

        get '/up'

        expect(response.headers).not_to have_key('X-Action-Required')
      end

      it 'is absent while services start' do
        allow(Orchestration::StackStatus).to receive(:overall).and_return(:starting)

        get '/up'

        expect(response.headers).not_to have_key('X-Action-Required')
      end

      %i[restart_required partial error].each do |state|
        it "is set when the stack is #{state}" do
          allow(Orchestration::StackStatus).to receive(:overall).and_return(state)

          get '/up'

          expect(response.headers['X-Action-Required']).to eq('1')
        end
      end

      it 'is set when the configuration is incomplete' do
        with_config_yaml
        allow(Orchestration::StackStatus).to receive(:overall).and_return(:ok)

        get '/up'

        expect(response.headers['X-Action-Required']).to eq('1')
      end

      it 'is left out without failing the health check when the check raises' do
        allow(Orchestration::StackStatus).to receive(:overall).and_raise(StandardError, 'boom')

        get '/up'

        expect(response).to have_http_status(:ok)
        expect(response.headers).not_to have_key('X-Action-Required')
      end
    end
  end
end
