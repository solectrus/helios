import { Controller } from '@hotwired/stimulus';
import { prefersReducedMotion } from '../utils/prefers_reduced_motion';

// Briefly enlarges a sensor value when its timestamp advances, giving a subtle
// "just updated" cue. It animates only when one reading is replaced by a newer
// one: the initial render, a hard reload (where the first poll fills empty
// cells), and a morph that leaves the timestamp unchanged all stay still.
export default class extends Controller {
  static values = { timestamp: String };

  declare readonly timestampValue: string;

  timestampValueChanged(value: string, previousValue: string) {
    // Stimulus only fires this on an actual change, so we just guard the
    // edges: skip the connect call and the first population of an empty cell
    // (no previous reading), and skip when a reading is cleared.
    if (!previousValue || !value) return;

    this.flash();
  }

  private flash() {
    if (prefersReducedMotion()) return;

    const target = this.element.firstElementChild as HTMLElement | null;
    if (!target?.animate) return;

    target.animate(
      [
        { transform: 'scale(1)' },
        { transform: 'scale(1.3)', offset: 0.3 },
        { transform: 'scale(1)' },
      ],
      { duration: 450, easing: 'ease-out' },
    );
  }
}
