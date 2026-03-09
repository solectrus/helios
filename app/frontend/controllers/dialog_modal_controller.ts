import { Controller } from '@hotwired/stimulus';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame', 'confirm'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;
  declare confirmTarget: HTMLDialogElement;

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
    this.element.addEventListener('keydown', this.handleKeyDown);
    this.element.addEventListener('cancel', this.handleCancel);
    this.element.addEventListener('submit', this.handleDialogFormSubmit);

    if (this.hasFrameTarget) {
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
    this.element.removeEventListener('keydown', this.handleKeyDown);
    this.element.removeEventListener('cancel', this.handleCancel);
    this.element.removeEventListener('submit', this.handleDialogFormSubmit);

    if (this.hasFrameTarget) {
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
    this.element.showModal();
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

  // Intercept Escape at keydown level, before the browser fires cancel
  private handleKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'Escape') return;

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
