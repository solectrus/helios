import { Application } from '@hotwired/stimulus';
import { registerControllers } from 'stimulus-vite-helpers';
import type { TurboFrameMissingEvent } from '@hotwired/turbo';
import * as Turbo from '@hotwired/turbo';

// Start Stimulus application
export const application = Application.start();

// Configure Stimulus development experience
application.debug = false; // process.env.NODE_ENV === 'development';

// Register both the global frontend controllers and the ViewComponent
// sidecar controllers. Vite resolves both globs at build time into a single
// module map.
registerControllers(
  application,
  import.meta.glob(
    [
      '../controllers/*_controller.{js,ts}',
      '../../components/**/*_controller.{js,ts}',
    ],
    { eager: true },
  ),
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
    drive: {
      progressBarDelay: number;
    };
    forms: {
      confirm: (
        message: string,
        form: HTMLFormElement,
        submitter?: HTMLElement,
      ) => Promise<boolean>;
    };
  };
}

// Turbo waits 500 ms before it shows the progress bar, which is tuned for
// hosts that answer most navigations within that window. HELIOS runs on
// Raspberry Pi class hardware where a page can take a second or more, so the
// default turns the first half second into a dead moment. 100 ms is late
// enough that a fast navigation still completes without any bar appearing.
Turbo.config.drive.progressBarDelay = 100;

Turbo.config.forms.confirm = (
  message: string,
  form: HTMLFormElement,
  submitter?: HTMLElement,
) => {
  const dialog = document.getElementById(
    'turbo-confirm-dialog',
  ) as HTMLDialogElement | null;
  if (!dialog) return Promise.resolve(confirm(message));

  // innerHTML: all confirm messages come from trusted i18n yamls and may
  // include light formatting (<br>, <strong>). Interpolated values come
  // from server-side helpers (l(), service names from compose), not user
  // input.
  const messageEl = dialog.querySelector('[data-confirm-message]');
  if (messageEl) messageEl.innerHTML = message;

  // Optional bold title above the message. Hidden again when not supplied,
  // so confirms without a title keep the plain single-paragraph layout.
  const title =
    submitter?.dataset.turboConfirmTitle || form.dataset.turboConfirmTitle;
  const titleEl = dialog.querySelector('[data-confirm-title]');
  if (titleEl) {
    titleEl.textContent = title ?? '';
    titleEl.classList.toggle('hidden', !title);
  }

  const acceptButton = dialog.querySelector<HTMLButtonElement>(
    '[data-confirm-accept]',
  );
  const variant =
    submitter?.dataset.turboConfirmVariant || form.dataset.turboConfirmVariant;
  const buttonText =
    submitter?.dataset.turboConfirmButton || form.dataset.turboConfirmButton;

  if (acceptButton) {
    acceptButton.classList.toggle('btn-error', variant === 'error');
    acceptButton.classList.toggle('btn-warning', variant !== 'error');
    // Capture default label on first call so we can restore it when no
    // override is supplied. textContent is trimmed because the layout
    // indents the button content for readability.
    acceptButton.dataset.confirmDefault ??=
      acceptButton.textContent?.trim() ?? '';
    acceptButton.textContent =
      buttonText || acceptButton.dataset.confirmDefault;
  }

  const icon = dialog.querySelector('[data-confirm-icon]');
  icon?.classList.toggle('hidden', variant !== 'error');

  return new Promise<boolean>((resolve) => {
    dialog.addEventListener(
      'close',
      () => {
        // Browser restores focus to the submitter on close. If the submitter
        // lives inside a CSS focus-driven container (e.g. daisyUI dropdown),
        // the container would re-open. Drop the focus so any such container
        // collapses.
        if (submitter instanceof HTMLElement) submitter.blur();
        resolve(dialog.returnValue === 'confirm');
      },
      { once: true },
    );
    // Reset returnValue: it persists across opens, and ESC / backdrop submitters
    // without an explicit value don't overwrite it. Without this, a previous
    // 'confirm' would leak into the next interaction and be treated as accepted.
    dialog.returnValue = '';
    dialog.showModal();
  });
};
