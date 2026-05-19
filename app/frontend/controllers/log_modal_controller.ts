import { Controller } from '@hotwired/stimulus';
import { loadingSpinner } from '../utils/loading_spinner';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;

  connect() {
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

    this.element.addEventListener('close', this.handleClose);
  }

  disconnect() {
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

    this.element.removeEventListener('close', this.handleClose);
  }

  // Open the modal as soon as the frame starts fetching, so the spinner is
  // visible immediately instead of waiting for the logs to arrive.
  private handleFrameFetchStart = (event: Event) => {
    if (event.target !== this.frameTarget) return;
    this.open();
  };

  private handleFrameLoad = () => {
    this.open();
  };

  private open() {
    if (!this.element.open) this.element.showModal();
  }

  private handleClose = () => {
    // Reset frame content so next open shows spinner and fetches fresh logs
    if (this.hasFrameTarget) {
      this.frameTarget.replaceChildren(loadingSpinner());
      this.frameTarget.removeAttribute('src');
      this.frameTarget.removeAttribute('complete');
    }
  };
}
