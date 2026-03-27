import { Application } from '@hotwired/stimulus';
import { registerControllers } from 'stimulus-vite-helpers';
import type { TurboFrameMissingEvent } from '@hotwired/turbo';
import * as Turbo from '@hotwired/turbo';

// Start Stimulus application
export const application = Application.start();

// Configure Stimulus development experience
application.debug = false; // process.env.NODE_ENV === 'development';

// Load and register global controllers
registerControllers(
  application,
  import.meta.glob('../controllers/*_controller.{js,ts}', { eager: true }),
);

// Load and register view_components controllers
registerControllers(
  application,
  import.meta.glob('../../components/**/*_controller.{js,ts}', { eager: true }),
);

// Error handling for missing Turbo frames
document.addEventListener('turbo:frame-missing', (event) => {
  const {
    detail: { response },
  } = event as TurboFrameMissingEvent;
  event.preventDefault();
  window.location.href = response.url;
});

Turbo.StreamActions.redirect = function (this: Element) {
  const target = this.getAttribute('target');
  if (target) {
    Turbo.visit(target);
  }
};

// Replace browser confirm() with a daisyUI modal dialog.
// The dialog element must exist in the layout with id="turbo-confirm-dialog".
// Buttons inside use value="confirm" / value="cancel" with method="dialog"
// so that dialog.returnValue reflects the user's choice.
declare module '@hotwired/turbo' {
  const config: {
    forms: {
      confirm: (message: string, element: HTMLFormElement) => Promise<boolean>;
    };
  };
}

Turbo.config.forms.confirm = (message: string) => {
  const dialog = document.getElementById(
    'turbo-confirm-dialog',
  ) as HTMLDialogElement | null;
  if (!dialog) return Promise.resolve(confirm(message));

  const messageEl = dialog.querySelector('[data-confirm-message]');
  if (messageEl) messageEl.textContent = message;

  return new Promise<boolean>((resolve) => {
    dialog.addEventListener(
      'close',
      () => resolve(dialog.returnValue === 'confirm'),
      { once: true },
    );
    dialog.showModal();
  });
};
