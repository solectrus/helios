import { Controller } from '@hotwired/stimulus';
import { loadingSpinner } from '../utils/loading_spinner';
import { attachFrameModalAutoOpen } from '../utils/frame_modal_auto_open';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;

  private trigger: HTMLElement | null = null;
  private detachFrameAutoOpen: (() => void) | null = null;

  connect() {
    if (this.hasFrameTarget) {
      this.detachFrameAutoOpen = attachFrameModalAutoOpen({
        frame: this.frameTarget,
        open: () => {
          this.captureTrigger();
          this.open();
        },
      });
    }

    this.element.addEventListener('close', this.handleClose);
  }

  disconnect() {
    this.detachFrameAutoOpen?.();
    this.detachFrameAutoOpen = null;
    this.element.removeEventListener('close', this.handleClose);
  }

  private open() {
    if (!this.element.open) this.element.showModal();
  }

  // Remember the element that triggered the modal so we can strip the focus
  // ring the browser restores onto it after the dialog closes (notably via
  // ESC, which counts as keyboard and matches :focus-visible).
  private captureTrigger() {
    if (this.trigger) return;
    const active = document.activeElement;
    if (active instanceof HTMLElement && active !== document.body) {
      this.trigger = active;
    }
  }

  private handleClose = () => {
    // Reset frame content so next open shows spinner and fetches fresh logs
    if (this.hasFrameTarget) {
      this.frameTarget.replaceChildren(loadingSpinner());
      this.frameTarget.removeAttribute('src');
      this.frameTarget.removeAttribute('complete');
    }

    this.trigger?.blur();
    this.trigger = null;
  };
}
