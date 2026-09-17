import { describe, it, expect, afterEach } from 'vitest';
import { Application } from '@hotwired/stimulus';
import SettingSectionComponentController from '@components/setting_section/component_controller';

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

// The card of a source that is not set up yet: dimmed, its links inert, and
// the switch the one thing that reacts. The title link is what opens the
// survey, the card being the edit button.
const CARD = `
  <article data-controller="setting-section--component"
           data-setting-section--component-on-title-value="Switch off"
           data-setting-section--component-off-title-value="Activate"
           class="hover:border-primary/40">
    <span data-tip="Activate" data-setting-section--component-target="tip">
      <input type="checkbox"
             data-setting-section--component-target="switch"
             data-action="change->setting-section--component#toggle">
    </span>
    <div class="opacity-55" data-setting-section--component-target="dim">
      <a href="/configuration/settings/new?setting=senec" inert
         data-setting-section--component-target="link edit">SENEC</a>
    </div>
    <div class="opacity-55" data-setting-section--component-target="dim">
      <a href="/sensors" inert data-setting-section--component-target="link">Sensors</a>
    </div>
  </article>
  <dialog id="setting-modal"></dialog>`;

describe('SettingSectionComponentController', () => {
  let app: Application;

  afterEach(() => {
    app?.stop();
    document.body.innerHTML = '';
  });

  async function start() {
    document.body.innerHTML = CARD;
    app = Application.start();
    app.register(
      'setting-section--component',
      SettingSectionComponentController,
    );
    await tick();

    return {
      card: document.querySelector('article') as HTMLElement,
      checkbox: document.querySelector('input') as HTMLInputElement,
      edit: document.querySelector('a') as HTMLAnchorElement,
      sensors: document.querySelectorAll('a')[1] as HTMLAnchorElement,
      tip: document.querySelector('[data-tip]') as HTMLElement,
      dialog: document.querySelector('dialog') as HTMLDialogElement,
    };
  }

  // The dimming sits on the body and the footer, so the switch and its tooltip
  // stay readable while the source is off. Both parts answer together.
  function dimmed() {
    const parts = [
      ...document.querySelectorAll(
        '[data-setting-section--component-target~="dim"]',
      ),
    ];

    return parts.every((part) => part.classList.contains('opacity-55'));
  }

  it('opens the card and its survey when the switch is ticked', async () => {
    const { checkbox, edit, sensors, tip } = await start();
    let opened = false;
    edit.addEventListener('click', (event) => {
      event.preventDefault();
      opened = true;
    });

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));

    expect(dimmed()).toBe(false);
    expect(edit.hasAttribute('inert')).toBe(false);
    expect(sensors.hasAttribute('inert')).toBe(false);
    expect(tip.dataset.tip).toBe('Switch off');
    expect(opened).toBe(true);
  });

  // Switching a source on stores nothing, so a survey that is closed without
  // saving leaves the card the way it came. A saved one redirects the whole
  // page and never reaches this handler.
  it('dims the card again when the survey is dismissed', async () => {
    const { checkbox, edit, tip, dialog } = await start();
    edit.addEventListener('click', (event) => event.preventDefault());

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));
    dialog.dispatchEvent(new Event('close'));

    expect(dimmed()).toBe(true);
    expect(checkbox.checked).toBe(false);
    expect(edit.hasAttribute('inert')).toBe(true);
    expect(tip.dataset.tip).toBe('Activate');
  });

  // The dialog closes before the answer to the save arrives. Dimming the card
  // in between would show it switched off for a moment.
  it('keeps the card on while the survey is being saved', async () => {
    const { checkbox, edit, dialog } = await start();
    edit.addEventListener('click', (event) => event.preventDefault());

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));
    dialog.dispatchEvent(new Event('turbo:submit-start', { bubbles: true }));
    dialog.dispatchEvent(new Event('close'));

    expect(dimmed()).toBe(false);
    expect(checkbox.checked).toBe(true);
  });

  // A refused save re-renders the survey, so the card is unsaved again.
  it('dims the card when a refused save is dismissed', async () => {
    const { checkbox, edit, dialog } = await start();
    edit.addEventListener('click', (event) => event.preventDefault());

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));
    dialog.dispatchEvent(new Event('turbo:submit-start', { bubbles: true }));
    dialog.dispatchEvent(
      new CustomEvent('turbo:submit-end', { detail: { success: false } }),
    );
    dialog.dispatchEvent(new Event('close'));

    expect(dimmed()).toBe(true);
    expect(checkbox.checked).toBe(false);
  });

  // Nothing was stored, so unticking puts the card back the way it came.
  it('closes the card again when the switch is unticked', async () => {
    const { checkbox, edit, sensors, tip } = await start();

    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));
    checkbox.checked = false;
    checkbox.dispatchEvent(new Event('change'));

    expect(dimmed()).toBe(true);
    expect(edit.hasAttribute('inert')).toBe(true);
    expect(sensors.hasAttribute('inert')).toBe(true);
    expect(tip.dataset.tip).toBe('Activate');
  });
});
