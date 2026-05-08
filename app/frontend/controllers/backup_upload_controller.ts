import { Controller } from '@hotwired/stimulus';

// Submits the surrounding form as soon as a file is picked. The visible
// upload button is type="button" and forwards its click to the hidden
// <input type="file">; the change event then triggers the submit.
export default class extends Controller {
  static targets = ['input'];

  declare inputTarget: HTMLInputElement;

  open() {
    this.inputTarget.click();
  }

  submit() {
    if (this.inputTarget.files && this.inputTarget.files.length > 0) {
      this.inputTarget.form?.requestSubmit();
    }
  }
}
