import { Controller } from '@hotwired/stimulus';

// A data source that is not set up yet shows a dimmed card whose only live
// control is the switch. Ticking it lifts the dimming and opens the survey
// right away, where the source gets its host, its provider, its broker.
//
// Nothing is stored at this point, and nothing can be: a source without
// settings reads nothing, so there is no state to save until the survey is
// saved. The switch is therefore a decision of this page alone, and a survey
// that is dismissed without saving takes it back. Switching a source off is
// the other half and does reach the server, because settings have to be taken
// away (see the button in the template).
export default class extends Controller {
  static targets = ['link', 'edit', 'tip', 'switch', 'dim'];
  static values = { onTitle: String, offTitle: String };

  declare linkTargets: HTMLElement[];
  declare dimTargets: HTMLElement[];
  declare editTarget: HTMLElement;
  declare hasEditTarget: boolean;
  declare tipTarget: HTMLElement;
  declare hasTipTarget: boolean;
  declare switchTarget: HTMLInputElement;
  declare hasSwitchTarget: boolean;
  declare onTitleValue: string;
  declare offTitleValue: string;

  private dialog: HTMLDialogElement | null = null;
  private saving = false;

  // A dismissed survey leaves nothing behind, so the card goes back to the way
  // it came. A saved one is on its way to the server at this point: the dialog
  // closes before the answer arrives, and dimming the card in between would
  // show it switched off for a moment.
  private closeSurvey = () => {
    if (!this.saving) this.apply(false);
    this.detachSurvey();
  };

  private startedSaving = () => {
    this.saving = true;
  };

  // A save the server refuses re-renders the survey in the open dialog, so the
  // card is back to being unsaved and the next dismissal counts again.
  private finishedSaving = (event: Event) => {
    const { success } = (event as CustomEvent<{ success: boolean }>).detail;
    if (!success) this.saving = false;
  };

  disconnect() {
    this.detachSurvey();
  }

  toggle(event: Event) {
    const checked = (event.target as HTMLInputElement).checked;

    this.apply(checked);
    if (checked) this.openSurvey();
  }

  private apply(checked: boolean) {
    if (this.hasSwitchTarget) this.switchTarget.checked = checked;

    // The same split the server renders (see component.html.erb). The dimming
    // sits on the body and the footer rather than the card, so the switch and
    // its tooltip stay readable: `opacity` caps every descendant, and a card
    // that carried it would take the tooltip down with it. The border of the
    // card answers the pointer either way and needs no swap.
    this.dimTargets.forEach((part) =>
      part.classList.toggle('opacity-55', !checked),
    );
    this.linkTargets.forEach((link) => link.toggleAttribute('inert', !checked));

    // The tooltip names what the switch would do next, so it turns around with
    // it. Rendered by the server for the state the page arrived in.
    if (this.hasTipTarget) {
      this.tipTarget.dataset.tip = checked
        ? this.onTitleValue
        : this.offTitleValue;
    }
  }

  // The settings are the point of switching a source on, so the survey opens
  // by itself. Turbo handles this click like any other and loads the modal
  // frame the link points at.
  //
  // A saved survey never reaches the close handler: it answers with a redirect
  // of the whole page, and the card that comes back is drawn by the server.
  private openSurvey() {
    if (!this.hasEditTarget) return;

    this.saving = false;
    this.dialog = document.getElementById(
      'setting-modal',
    ) as HTMLDialogElement | null;
    this.dialog?.addEventListener('close', this.closeSurvey, { once: true });
    this.dialog?.addEventListener('turbo:submit-start', this.startedSaving);
    this.dialog?.addEventListener('turbo:submit-end', this.finishedSaving);

    this.editTarget.click();
  }

  private detachSurvey() {
    this.dialog?.removeEventListener('close', this.closeSurvey);
    this.dialog?.removeEventListener('turbo:submit-start', this.startedSaving);
    this.dialog?.removeEventListener('turbo:submit-end', this.finishedSaving);
    this.dialog = null;
  }
}
