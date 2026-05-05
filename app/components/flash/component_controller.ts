import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static values = { delay: Number };
  declare delayValue: number;

  private timeoutId?: number;

  connect() {
    this.timeoutId = window.setTimeout(() => this.dismiss(), this.delayValue);
  }

  disconnect() {
    if (this.timeoutId !== undefined) window.clearTimeout(this.timeoutId);
  }

  private dismiss() {
    this.element.addEventListener(
      'transitionend',
      () => this.element.remove(),
      {
        once: true,
      },
    );
    this.element.classList.add('transition', 'duration-500', 'opacity-0');
  }
}
