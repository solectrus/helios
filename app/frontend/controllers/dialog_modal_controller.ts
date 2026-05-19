import { Controller } from '@hotwired/stimulus';
import { loadingSpinner } from '../utils/loading_spinner';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame', 'confirm', 'box'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;
  declare confirmTarget: HTMLDialogElement;
  declare boxTarget: HTMLElement;

  private dirty = false;
  private confirming = false;
  private pendingResolve: ((discard: boolean) => void) | null = null;

  connect() {
    this.element.addEventListener(
      'survey:formSubmitted',
      this.handleFormSubmitted,
    );
    this.element.addEventListener(
      'survey:valueChanged',
      this.handleValueChanged,
    );
    this.element.addEventListener('input', this.handleInput);
    this.element.addEventListener('cancel', this.handleCancel);
    this.element.addEventListener('submit', this.handleDialogFormSubmit);

    // Listen on document (capture phase) so ESC is caught regardless of
    // focus location — SurveyJS may render popups on document.body that
    // move focus outside the <dialog>.
    document.addEventListener('keydown', this.handleKeyDown, true);

    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener(
        'turbo:before-fetch-request',
        this.handleFrameFetchStart,
      );
      this.frameTarget.addEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }
  }

  disconnect() {
    this.element.removeEventListener(
      'survey:formSubmitted',
      this.handleFormSubmitted,
    );
    this.element.removeEventListener(
      'survey:valueChanged',
      this.handleValueChanged,
    );
    this.element.removeEventListener('input', this.handleInput);
    this.element.removeEventListener('cancel', this.handleCancel);
    this.element.removeEventListener('submit', this.handleDialogFormSubmit);

    document.removeEventListener('keydown', this.handleKeyDown, true);

    if (this.hasFrameTarget) {
      this.frameTarget.removeEventListener(
        'turbo:before-fetch-request',
        this.handleFrameFetchStart,
      );
      this.frameTarget.removeEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }

    this.resolveConfirm(false);
  }

  open() {
    this.dirty = false;
    this.confirming = false;
    if (!this.element.open) this.element.showModal();
    this.boxTarget.focus();
  }

  close() {
    this.dirty = false;
    this.confirming = false;
    this.element.close();
  }

  confirmCancel() {
    this.resolveConfirm(false);
  }

  confirmDiscard() {
    this.resolveConfirm(true);
  }

  private resolveConfirm(discard: boolean) {
    this.confirmTarget.close();
    this.confirming = false;
    this.pendingResolve?.(discard);
    this.pendingResolve = null;
  }

  // Open the modal as soon as the frame starts fetching, so the user sees a
  // spinner immediately instead of waiting for the response to arrive.
  private handleFrameFetchStart = (event: Event) => {
    // Only react to navigation of the frame itself, not form submissions
    // bubbling up from inside the modal.
    if (event.target !== this.frameTarget) return;

    // Replace any stale content from a previous open with the spinner.
    this.frameTarget.replaceChildren(loadingSpinner());
    this.open();
  };

  private handleFrameLoad = () => {
    this.open();
  };

  private handleFormSubmitted = () => {
    this.close();
  };

  private handleValueChanged = () => {
    this.dirty = true;
  };

  private handleInput = () => {
    this.dirty = true;
  };

  private showConfirm(): Promise<boolean> {
    return new Promise((resolve) => {
      this.pendingResolve = resolve;
      this.confirming = true;
      this.confirmTarget.showModal();
    });
  }

  // Intercept Escape via document-level capture, before any other handler
  private handleKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'Escape') return;

    // Only act when our dialog is open
    if (!this.element.open) return;

    // Stop the browser from generating a cancel event
    event.preventDefault();
    event.stopPropagation();

    // ESC inside confirm dialog = keep editing
    if (this.confirming) {
      this.resolveConfirm(false);
      return;
    }

    // Not dirty = close normally
    if (!this.dirty) {
      this.close();
      return;
    }

    // Dirty = ask for confirmation
    this.showConfirm().then((discard) => {
      if (discard) this.close();
    });
  };

  // Fallback: prevent native dialog close on cancel
  private handleCancel = (event: Event) => {
    event.preventDefault();
  };

  // X button and backdrop use <form method="dialog"> to close
  private handleDialogFormSubmit = (event: SubmitEvent) => {
    const form = event.target as HTMLFormElement;
    if (form.method !== 'dialog') return;

    if (!this.dirty) return;

    event.preventDefault();
    this.showConfirm().then((discard) => {
      if (discard) this.close();
    });
  };
}
