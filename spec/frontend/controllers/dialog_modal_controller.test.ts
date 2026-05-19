import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Application } from '@hotwired/stimulus';
import DialogModalController from '@/controllers/dialog_modal_controller';

function createDOM() {
  document.body.innerHTML = `
    <template id="loading-spinner">
      <div class="flex justify-center py-8"><span class="loading loading-spinner loading-lg"></span></div>
    </template>
    <dialog id="modal" data-controller="dialog-modal">
      <div data-dialog-modal-target="box" tabindex="-1">
        <turbo-frame id="frame" data-dialog-modal-target="frame"></turbo-frame>
        <input type="text" id="test-input" />
        <form method="dialog" id="close-form">
          <button type="submit" id="close-btn">X</button>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop" id="backdrop-form">
        <button>close</button>
      </form>
      <dialog id="confirm" data-dialog-modal-target="confirm">
        <button id="keep-editing" data-action="dialog-modal#confirmCancel">Keep editing</button>
        <button id="discard" data-action="dialog-modal#confirmDiscard">Discard</button>
      </dialog>
    </dialog>
  `;

  return {
    modal: document.getElementById('modal') as HTMLDialogElement,
    confirm: document.getElementById('confirm') as HTMLDialogElement,
    frame: document.getElementById('frame') as HTMLElement,
    input: document.getElementById('test-input') as HTMLInputElement,
    closeForm: document.getElementById('close-form') as HTMLFormElement,
    keepEditingBtn: document.getElementById(
      'keep-editing',
    ) as HTMLButtonElement,
    discardBtn: document.getElementById('discard') as HTMLButtonElement,
  };
}

function pressEscape(target: HTMLElement) {
  const event = new KeyboardEvent('keydown', {
    key: 'Escape',
    bubbles: true,
    cancelable: true,
  });
  target.dispatchEvent(event);
  return event;
}

function typeInInput(input: HTMLInputElement, value: string) {
  input.value = value;
  input.dispatchEvent(new Event('input', { bubbles: true }));
}

function dispatchSurveyValueChanged(modal: HTMLElement) {
  modal.dispatchEvent(
    new CustomEvent('survey:valueChanged', { bubbles: true }),
  );
}

function dispatchSurveyFormSubmitted(modal: HTMLElement) {
  modal.dispatchEvent(
    new CustomEvent('survey:formSubmitted', { bubbles: true }),
  );
}

function mockDialog(dialog: HTMLDialogElement) {
  dialog.showModal = () => {
    dialog.setAttribute('open', '');
  };
  dialog.close = () => {
    dialog.removeAttribute('open');
  };
}

function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('DialogModalController', () => {
  let app: Application;
  let dom: ReturnType<typeof createDOM>;

  beforeEach(async () => {
    dom = createDOM();

    // Stub showModal/close since happy-dom doesn't fully support them
    mockDialog(dom.modal);
    mockDialog(dom.confirm);

    app = Application.start();
    app.register('dialog-modal', DialogModalController);

    // Wait for Stimulus to connect
    await tick();
  });

  afterEach(() => {
    app.stop();
    document.body.innerHTML = '';
  });

  function isModalOpen() {
    return dom.modal.hasAttribute('open');
  }

  function isConfirmOpen() {
    return dom.confirm.hasAttribute('open');
  }

  describe('opening and closing', () => {
    it('opens via turbo:frame-load', () => {
      dom.frame.dispatchEvent(new Event('turbo:frame-load'));

      expect(isModalOpen()).toBe(true);
    });

    it('opens immediately when the frame starts fetching', () => {
      dom.frame.dispatchEvent(
        new Event('turbo:before-fetch-request', { bubbles: true }),
      );

      expect(isModalOpen()).toBe(true);
    });

    it('replaces stale frame content with a spinner on fetch start', () => {
      dom.frame.innerHTML = '<p>stale content</p>';
      dom.frame.dispatchEvent(
        new Event('turbo:before-fetch-request', { bubbles: true }),
      );

      expect(dom.frame.querySelector('.loading')).not.toBeNull();
      expect(dom.frame.textContent).not.toContain('stale content');
    });

    it('ignores turbo:before-fetch-request bubbling from inside the frame', () => {
      // A form submission inside the modal must not re-open the frame.
      const innerForm = document.createElement('form');
      dom.frame.appendChild(innerForm);
      innerForm.dispatchEvent(
        new Event('turbo:before-fetch-request', { bubbles: true }),
      );

      expect(isModalOpen()).toBe(false);
    });

    it('ESC closes when not dirty', () => {
      dom.modal.showModal();
      pressEscape(dom.modal);

      expect(isModalOpen()).toBe(false);
    });

    it('closes on survey:formSubmitted', () => {
      dom.modal.showModal();
      dispatchSurveyFormSubmitted(dom.modal);

      expect(isModalOpen()).toBe(false);
    });
  });

  describe('dirty tracking', () => {
    it('becomes dirty on native input event', () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'hello');
      pressEscape(dom.modal);

      expect(isConfirmOpen()).toBe(true);
    });

    it('becomes dirty on survey:valueChanged', () => {
      dom.modal.showModal();
      dispatchSurveyValueChanged(dom.modal);
      pressEscape(dom.modal);

      expect(isConfirmOpen()).toBe(true);
    });

    it('resets dirty on open', () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'hello');

      // Re-open resets dirty
      dom.frame.dispatchEvent(new Event('turbo:frame-load'));
      pressEscape(dom.modal);

      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(false);
    });
  });

  describe('ESC with dirty state', () => {
    it('shows confirm dialog instead of closing', () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');
      pressEscape(dom.modal);

      expect(isModalOpen()).toBe(true);
      expect(isConfirmOpen()).toBe(true);
    });

    it('keeps modal open when choosing "Keep editing"', async () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');
      pressEscape(dom.modal);

      dom.keepEditingBtn.click();
      await tick();

      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(true);
    });

    it('closes modal when choosing "Discard"', async () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');
      pressEscape(dom.modal);

      dom.discardBtn.click();
      await tick();

      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(false);
    });

    it('ESC in confirm dialog keeps editing', () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');
      pressEscape(dom.modal);

      expect(isConfirmOpen()).toBe(true);

      // ESC inside confirm = keep editing
      pressEscape(dom.confirm);

      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(true);
    });

    it('repeated ESC cycle works correctly', async () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');

      // 1st ESC: confirm appears
      pressEscape(dom.modal);
      expect(isConfirmOpen()).toBe(true);
      expect(isModalOpen()).toBe(true);

      // 2nd ESC: confirm dismissed (keep editing)
      pressEscape(dom.confirm);
      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(true);

      // 3rd ESC: confirm appears again, modal stays open
      pressEscape(dom.modal);
      expect(isConfirmOpen()).toBe(true);
      expect(isModalOpen()).toBe(true);

      // Discard: both close
      dom.discardBtn.click();
      await tick();
      expect(isConfirmOpen()).toBe(false);
      expect(isModalOpen()).toBe(false);
    });
  });

  describe('X button and backdrop with dirty state', () => {
    it('shows confirm when clicking X while dirty', () => {
      dom.modal.showModal();
      typeInInput(dom.input, 'changed');

      const event = new SubmitEvent('submit', { bubbles: true });
      dom.closeForm.dispatchEvent(event);

      expect(isConfirmOpen()).toBe(true);
      expect(isModalOpen()).toBe(true);
    });

    it('closes normally when clicking X while not dirty', () => {
      dom.modal.showModal();

      const event = new SubmitEvent('submit', { bubbles: true });
      dom.closeForm.dispatchEvent(event);

      // Not dirty, so interceptClose returns early and native form submit closes dialog
      expect(isConfirmOpen()).toBe(false);
    });
  });

  describe('ESC from outside dialog', () => {
    it('closes modal even when focus is outside the dialog', () => {
      dom.modal.showModal();

      // Simulate focus on an element outside the dialog (e.g. SurveyJS popup)
      const outsideElement = document.createElement('div');
      document.body.appendChild(outsideElement);
      pressEscape(outsideElement);

      expect(isModalOpen()).toBe(false);
      outsideElement.remove();
    });
  });

  describe('ESC preventDefault', () => {
    it('prevents default on ESC keydown', () => {
      dom.modal.showModal();
      const event = pressEscape(dom.modal);

      expect(event.defaultPrevented).toBe(true);
    });

    it('prevents default on cancel event as fallback', () => {
      dom.modal.showModal();
      const event = new Event('cancel', { bubbles: true, cancelable: true });
      dom.modal.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
    });
  });
});
