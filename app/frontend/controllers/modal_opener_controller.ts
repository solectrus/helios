import { Controller, type ActionEvent } from '@hotwired/stimulus';

export default class extends Controller {
  private closeDialog = () => {
    this.element.closest('dialog')?.close();
  };

  connect() {
    // When attached to a form inside a <dialog>, close the dialog on submit.
    // Without this, Turbo morph (active on configuration pages) strips the
    // `open` attribute but the dialog stays in the top layer, leaving the
    // page inert until a full reload.
    if (this.element instanceof HTMLFormElement) {
      this.element.addEventListener('submit', this.closeDialog);
    }
  }

  disconnect() {
    if (this.element instanceof HTMLFormElement) {
      this.element.removeEventListener('submit', this.closeDialog);
    }
  }

  open(event: ActionEvent) {
    const id = event.params.id as string;
    const dialog = document.getElementById(id);
    if (dialog instanceof HTMLDialogElement) dialog.showModal();
  }
}
