import { Controller } from '@hotwired/stimulus';

// Opens a confirm dialog before submitting a delete form.
// The dialog target contains the modal, the form target is the hidden delete form.
export default class extends Controller {
  static targets = ['dialog', 'form'];

  declare readonly dialogTarget: HTMLDialogElement;
  declare readonly formTarget: HTMLFormElement;

  requestDelete(event: Event) {
    event.preventDefault();
    this.dialogTarget.showModal();
  }

  confirm() {
    this.dialogTarget.close();
    this.formTarget.requestSubmit();
  }

  cancel() {
    this.dialogTarget.close();
  }
}
