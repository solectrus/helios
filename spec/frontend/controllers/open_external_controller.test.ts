import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';
import OpenExternalController from '@/controllers/open_external_controller';

function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('OpenExternalController', () => {
  let app: Application;
  let openSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(async () => {
    openSpy = vi.spyOn(window, 'open').mockImplementation(() => null);

    app = Application.start();
    app.register('open-external', OpenExternalController);

    await tick();
  });

  afterEach(() => {
    app.stop();
    document.body.innerHTML = '';
    openSpy.mockRestore();
  });

  // Insert the button, then wait a tick so Stimulus (which connects
  // asynchronously via its MutationObserver) wires up the action before the
  // click.
  async function clickButton(attrs: string) {
    document.body.innerHTML = `
      <button
        data-controller="open-external"
        data-action="click->open-external#open"
        ${attrs}
      >Open</button>
    `;
    await tick();
    const button = document.querySelector('button') as HTMLButtonElement;
    button.click();
  }

  it('opens an absolute URL in a new tab', async () => {
    await clickButton('data-url="https://dashboard.example.com"');

    expect(openSpy).toHaveBeenCalledWith(
      'https://dashboard.example.com',
      '_blank',
    );
  });

  it('opens a host-port URL at the current hostname', async () => {
    await clickButton('data-port="3000"');

    expect(openSpy).toHaveBeenCalledWith(
      `http://${window.location.hostname}:3000`,
      '_blank',
    );
  });

  it('prefers the absolute URL over the port when both are present', async () => {
    await clickButton(
      'data-url="https://dashboard.example.com" data-port="3000"',
    );

    expect(openSpy).toHaveBeenCalledTimes(1);
    expect(openSpy).toHaveBeenCalledWith(
      'https://dashboard.example.com',
      '_blank',
    );
  });

  it('does nothing when neither URL nor port is set', async () => {
    await clickButton('');

    expect(openSpy).not.toHaveBeenCalled();
  });
});
