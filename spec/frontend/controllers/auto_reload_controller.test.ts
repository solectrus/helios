import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';

const AutoReloadController = (
  await import('@/controllers/auto_reload_controller')
).default;

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

describe('AutoReloadController', () => {
  let app: Application;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      text: async () => '<turbo-frame id="backups-content"></turbo-frame>',
    });
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => {
    app?.stop();
    vi.unstubAllGlobals();
    document.body.innerHTML = '';
  });

  async function start(frameId: string) {
    document.body.innerHTML = `
      <turbo-frame id="${frameId}">
        <div data-controller="auto-reload"
             data-auto-reload-url-value="/backups"></div>
      </turbo-frame>`;

    app = Application.start();
    app.register('auto-reload', AutoReloadController);
    await tick();

    const root = document.querySelector(
      '[data-controller~="auto-reload"]',
    ) as HTMLElement;
    return app.getControllerForElementAndIdentifier(
      root,
      'auto-reload',
    ) as unknown as { refresh: () => Promise<void> };
  }

  // The poll must identify itself as a frame request for the enclosing frame,
  // so servers that lazy-load their body keyed on the Turbo-Frame header
  // return the real content instead of the shell's skeleton placeholder.
  it('sends the enclosing frame id as the Turbo-Frame header', async () => {
    const ctrl = await start('backups-content');

    await ctrl.refresh();

    expect(fetchMock).toHaveBeenCalledWith(
      '/backups',
      expect.objectContaining({
        headers: expect.objectContaining({
          Accept: 'text/html',
          'Turbo-Frame': 'backups-content',
        }),
      }),
    );
  });

  it('uses whichever frame actually encloses the controller', async () => {
    const ctrl = await start('csv-import-content');

    await ctrl.refresh();

    expect(fetchMock).toHaveBeenCalledWith(
      '/backups',
      expect.objectContaining({
        headers: expect.objectContaining({
          'Turbo-Frame': 'csv-import-content',
        }),
      }),
    );
  });
});
