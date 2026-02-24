import { Controller } from '@hotwired/stimulus';

export default class extends Controller<HTMLDialogElement> {
  static targets = ['frame'];

  declare frameTarget: HTMLElement;
  declare hasFrameTarget: boolean;

  connect() {
    // Close modal when survey form is submitted
    this.element.addEventListener(
      'survey:formSubmitted',
      this.handleFormSubmitted,
    );

    // Open modal when frame content is loaded
    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }
  }

  disconnect() {
    this.element.removeEventListener(
      'survey:formSubmitted',
      this.handleFormSubmitted,
    );

    if (this.hasFrameTarget) {
      this.frameTarget.removeEventListener(
        'turbo:frame-load',
        this.handleFrameLoad,
      );
    }
  }

  open() {
    this.element.showModal();
  }

  close() {
    this.element.close();
  }

  private handleFrameLoad = () => {
    this.open();
  };

  private handleFormSubmitted = () => {
    this.close();
  };
}
