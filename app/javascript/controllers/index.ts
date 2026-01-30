import { Application } from '@hotwired/stimulus';
import { registerControllers } from 'stimulus-vite-helpers';

import LoadingController from './loading_controller';

declare global {
  interface Window {
    Stimulus: Application;
  }
}

const application = Application.start();

// Configure Stimulus development experience
application.debug = false;
window.Stimulus = application;

application.register('loading', LoadingController);

// Load and register view_component controllers
registerControllers(
  application,
  import.meta.glob('../../components/**/*_controller.{js,ts}', { eager: true }),
);

export { application };
