import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';

// Action Cable's createConsumer would try to open a real WebSocket; replace
// it with a stub that captures the received() callback so tests can drive
// incoming lines synchronously.
type Mixin = {
  received: (data: unknown) => void;
  connected?: () => void;
  disconnected?: () => void;
};
let capturedMixin: Mixin | undefined;
const unsubscribe = vi.fn();

vi.mock('@/channels/consumer', () => ({
  default: {
    subscriptions: {
      create: (_channel: unknown, mixin: Mixin) => {
        capturedMixin = mixin;
        return { unsubscribe };
      },
    },
  },
}));

const LogViewerController = (
  await import('@/controllers/log_viewer_controller')
).default;

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

function setReducedMotion(reduce: boolean) {
  window.matchMedia = vi.fn().mockImplementation(() => ({
    matches: reduce,
    media: '(prefers-reduced-motion: reduce)',
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  })) as unknown as typeof window.matchMedia;
}

describe('LogViewerController', () => {
  let app: Application;

  beforeEach(() => {
    capturedMixin = undefined;
    unsubscribe.mockClear();
    setReducedMotion(false);
  });

  afterEach(() => {
    app?.stop();
    document.body.innerHTML = '';
  });

  async function start({ existingLines = 0 }: { existingLines?: number } = {}) {
    // Pad index to 4 digits so lexicographic ordering of data-ts matches
    // the visual order (the controller compares timestamps as strings).
    const lines = Array.from(
      { length: existingLines },
      (_, i) =>
        `<div data-ts="2026-01-01T00:00:${String(i).padStart(4, '0')}Z">existing ${i}</div>`,
    ).join('');

    document.body.innerHTML = `
      <div data-controller="log-viewer"
           data-log-viewer-service-value="mqtt-collector">
        <div data-log-viewer-target="scrollContainer">
          <pre data-log-viewer-target="output">${lines}</pre>
        </div>
        <button data-log-viewer-target="newLines" class="hidden"></button>
      </div>`;

    app = Application.start();
    app.register('log-viewer', LogViewerController);
    await tick();
  }

  function receive(line: string) {
    capturedMixin!.received({ html: line });
  }

  it('trims oldest lines once MAX_LINES is exceeded', async () => {
    // Pre-fill near the limit so a single inserted line forces a trim.
    await start({ existingLines: 5000 });
    const output = document.querySelector(
      '[data-log-viewer-target="output"]',
    ) as HTMLElement;
    expect(output.children.length).toBe(5000);

    receive(`<div data-ts="2030-01-01T00:00:00Z">brand new</div>`);

    expect(output.children.length).toBe(5000);
    // The freshly inserted line is kept, the oldest pre-existing line is gone.
    expect(output.lastElementChild?.textContent).toBe('brand new');
    expect(output.firstElementChild?.textContent).toBe('existing 1');
  });

  it('removes the log-line-enter class once the fade-in animation ends', async () => {
    await start();

    receive(`<div data-ts="2026-01-01T00:00:00Z">animated</div>`);

    const output = document.querySelector(
      '[data-log-viewer-target="output"]',
    ) as HTMLElement;
    const inserted = output.firstElementChild as HTMLElement;
    expect(inserted.classList.contains('log-line-enter')).toBe(true);

    inserted.dispatchEvent(new Event('animationend'));

    expect(inserted.classList.contains('log-line-enter')).toBe(false);
  });

  it('skips the fade-in animation when prefers-reduced-motion is set', async () => {
    setReducedMotion(true);
    await start();

    receive(`<div data-ts="2026-01-01T00:00:00Z">no-animation</div>`);

    const inserted = document.querySelector(
      '[data-log-viewer-target="output"] > *',
    ) as HTMLElement;
    expect(inserted.classList.contains('log-line-enter')).toBe(false);
  });

  it('shows the new-lines indicator when a line arrives while scrolled up', async () => {
    await start();

    // Bypass the geometry math: directly mark the controller as "not at the
    // bottom". happy-dom's layout numbers (scrollHeight/clientHeight) are
    // unreliable, so we set the state insertLine() reads.
    const root = document.querySelector(
      '[data-controller~="log-viewer"]',
    ) as HTMLElement;
    const ctrl = app.getControllerForElementAndIdentifier(
      root,
      'log-viewer',
    ) as unknown as { isScrolledToBottom: boolean };
    ctrl.isScrolledToBottom = false;

    const newLines = document.querySelector(
      '[data-log-viewer-target="newLines"]',
    ) as HTMLElement;
    expect(newLines.classList.contains('hidden')).toBe(true);

    receive(`<div data-ts="2026-01-01T00:00:00Z">while scrolled up</div>`);

    expect(newLines.classList.contains('hidden')).toBe(false);
  });

  it('unsubscribes from the channel when the controller disconnects', async () => {
    await start();
    expect(unsubscribe).not.toHaveBeenCalled();

    // Unloading the controller deterministically triggers disconnect();
    // relying on MutationObserver via innerHTML='' would be timing-coupled.
    app.unload('log-viewer');
    await tick();

    expect(unsubscribe).toHaveBeenCalledOnce();
  });
});
