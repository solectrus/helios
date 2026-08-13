import { Controller } from '@hotwired/stimulus';

// Moves the active marker to the clicked entry immediately, without waiting
// for the new page. On a Raspberry Pi a navigation can take a second or more,
// and the navigation bar is where the eye already is — reacting there on the
// spot is what separates "loading" from "nothing happened".
//
// Purely optimistic: every response carries the server-rendered active state
// and paints over whatever was set here, so an aborted or failed visit
// corrects itself on the next render.
export default class extends Controller<HTMLElement> {
  static targets = ['item'];
  static classes = ['active', 'inactive'];

  declare readonly itemTargets: HTMLElement[];
  declare readonly activeClasses: string[];
  declare readonly inactiveClasses: string[];

  mark(event: Event) {
    const clicked = (event.target as Element | null)?.closest<HTMLElement>(
      `[data-${this.identifier}-target="item"]`,
    );
    if (!clicked || !this.itemTargets.includes(clicked)) return;

    this.itemTargets.forEach((item) => {
      const active = item === clicked;

      item.classList.remove(
        ...(active ? this.inactiveClasses : this.activeClasses),
      );
      item.classList.add(
        ...(active ? this.activeClasses : this.inactiveClasses),
      );

      if (active) {
        item.setAttribute('aria-current', 'page');
      } else {
        item.removeAttribute('aria-current');
      }
    });
  }
}
