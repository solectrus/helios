// Only dropdown and tagbox questions carry a list popup.
type DropdownQuestion = {
  dropdownListModel?: {
    popupModel?: {
      getTargetCallback?: () => HTMLElement;
    };
  };
};

// A dropdown list renders inside its question, which puts it inside the
// scrolling modal box, and that box is what breaks it: the box clips the list
// at its edge, and SurveyJS scrolls the focused entry into view, which scrolls
// the box and trips SurveyJS' own scroll listener, closing the list right
// after it opened.
//
// Moving the list next to the dialog settles both, because the dialog does not
// scroll. SurveyJS keeps placing the list on the field that getTargetCallback
// names.
export class SurveyDropdowns {
  // Lists moved next to the dialog, each with the field it belongs to.
  private readonly lifted = new Map<HTMLElement, HTMLElement>();
  private host: HTMLElement | null = null;

  constructor(
    private readonly container: HTMLElement,
    private readonly dialog: HTMLElement | null,
  ) {}

  lift(question: unknown, htmlElement: HTMLElement) {
    const popup = (question as DropdownQuestion).dropdownListModel?.popupModel;
    if (!popup) return;

    // SurveyJS looks the list up inside the wrapper around .sv-popup, so the
    // wrapper moves along; the list on its own would lose its position.
    const wrapper = htmlElement.querySelector('.sv-popup')?.parentElement;
    const field = htmlElement.querySelector<HTMLElement>('.sd-dropdown');
    if (!wrapper || !field || this.lifted.has(wrapper)) return;

    // Only surveys that actually have a dropdown get a host.
    const host = this.popupHost();
    if (!host) return;

    // A page change or a condition can re-render the question, which leaves
    // its previous list behind with no field to belong to.
    this.dropStaleLists();

    popup.getTargetCallback = () => field;

    host.append(wrapper);
    this.lifted.set(wrapper, field);
  }

  // The dialog outlives the survey inside it, so the lists go with it.
  release() {
    this.host?.remove();
    this.host = null;
    this.lifted.clear();
  }

  private dropStaleLists() {
    this.lifted.forEach((field, wrapper) => {
      if (field.isConnected) return;
      wrapper.remove();
      this.lifted.delete(wrapper);
    });
  }

  // Lists outside the survey root would render bare, because survey-core
  // scopes its rules to that root and applyTheme writes the colors and radii
  // as custom properties on it. The host carries the same class and the same
  // properties, and stays a zero-sized box that paints nothing of its own —
  // the lists inside it position themselves.
  private popupHost(): HTMLElement | null {
    if (this.host) return this.host;

    const root = this.container.querySelector<HTMLElement>('.sd-root-modern');
    if (!this.dialog || !root) return null;

    const host = document.createElement('div');
    host.className = 'sd-root-modern sd-theme-root sjs-theme-overrides';
    Array.from(root.style).forEach((token) => {
      host.style.setProperty(token, root.style.getPropertyValue(token));
    });
    host.style.cssText += ';position:fixed;width:0;height:0;background:none';
    this.dialog.append(host);

    this.host = host;
    return host;
  }
}
