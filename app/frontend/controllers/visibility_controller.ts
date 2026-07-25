import { Controller } from '@hotwired/stimulus';
import type { FrameElement } from '@hotwired/turbo';
import { reloadFrame } from '@/utils/frame_recovery';

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

  // `reloadFrame` instead of `frame.reload()`: the latter is a no-op for a lazy
  // frame whose only load attempt failed, which is exactly the frame that needs
  // refreshing here.
  private refreshFrames() {
    this.frameTargets.forEach((frame) => reloadFrame(frame));
  }
}
