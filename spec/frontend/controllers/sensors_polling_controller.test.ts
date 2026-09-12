import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';

const SensorsPollingController = (
  await import('@/controllers/sensors_polling_controller')
).default;

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

describe('SensorsPollingController', () => {
  let app: Application;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      text: async () => '',
    });
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => {
    app?.stop();
    vi.unstubAllGlobals();
    document.documentElement.removeAttribute('data-turbo-preview');
    document.body.innerHTML = '';
  });

  async function start(enabled: boolean) {
    document.body.innerHTML = `
      <div data-controller="sensors-polling"
           data-sensors-polling-url-value="/sensors/readings"
           data-sensors-polling-enabled-value="${enabled}"></div>`;

    app = Application.start();
    app.register('sensors-polling', SensorsPollingController);
    await tick();
  }

  it('fetches the readings right away', async () => {
    await start(true);

    expect(fetchMock).toHaveBeenCalledWith(
      '/sensors/readings',
      expect.anything(),
    );
  });

  it('fetches nothing when polling is disabled', async () => {
    await start(false);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  // Turbo connects controllers in the cached preview as well, and replaces
  // that DOM with the real response a few frames later. Polling in the
  // preview would query InfluxDB twice for a single visit.
  it('fetches nothing while Turbo shows a cached preview', async () => {
    document.documentElement.setAttribute('data-turbo-preview', '');

    await start(true);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  // A preview that outlives the interval must not start querying either.
  it('starts no interval while Turbo shows a cached preview', async () => {
    vi.useFakeTimers();
    document.documentElement.setAttribute('data-turbo-preview', '');

    try {
      await start(true);
      vi.advanceTimersByTime(30_000);
      await tick();

      expect(fetchMock).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });
});
