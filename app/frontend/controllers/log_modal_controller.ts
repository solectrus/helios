import { Controller } from '@hotwired/stimulus';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;

  connect() {
    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }

    this.element.addEventListener('close', this.handleClose);
  }

  disconnect() {
    if (this.hasFrameTarget) {
      this.frameTarget.removeEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }

    this.element.removeEventListener('close', this.handleClose);
  }

  private handleFrameLoad = () => {
    this.element.showModal();
  };

  private handleClose = () => {
    // Reset frame content so next open shows spinner and fetches fresh logs
    if (this.hasFrameTarget) {
      this.frameTarget.innerHTML =
        '<div class="flex justify-center py-8"><span class="loading loading-spinner loading-lg"></span></div>';
      this.frameTarget.removeAttribute('src');
      this.frameTarget.removeAttribute('complete');
    }
  };
}
