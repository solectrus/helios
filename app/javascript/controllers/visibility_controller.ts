import { Controller } from '@hotwired/stimulus';
import type { FrameElement } from '@hotwired/turbo';

export default class extends Controller {
  static targets = ['frame'];

  declare frameTargets: FrameElement[];

  private boundHandler!: () => void;

  connect() {
    this.boundHandler = this.handleVisibilityChange.bind(this);
    document.addEventListener('visibilitychange', this.boundHandler);
  }

  disconnect() {
    document.removeEventListener('visibilitychange', this.boundHandler);
  }

  private handleVisibilityChange() {
    if (document.hidden) return;

    this.refreshFrames();
  }

  private refreshFrames() {
    this.frameTargets.forEach((frame) => {
      if (frame.src) {
        frame.reload();
      } else if (frame.dataset.src) {
        frame.src = frame.dataset.src;
      }
    });
  }
}
