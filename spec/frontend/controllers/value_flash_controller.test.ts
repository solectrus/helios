import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';
import ValueFlashController from '@/controllers/value_flash_controller';

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

describe('ValueFlashController', () => {
  let app: Application;
  let animateSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    animateSpy = vi.fn();
    // jsdom does not implement the Web Animations API.
    Element.prototype.animate =
      animateSpy as unknown as typeof Element.prototype.animate;
    vi.spyOn(window, 'matchMedia').mockReturnValue({
      matches: false,
    } as MediaQueryList);
  });

  afterEach(() => {
    app?.stop();
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  // td must live inside a table or jsdom drops it when set via innerHTML.
  function start(timestamp: string) {
    document.body.innerHTML = `<table><tbody><tr><td data-controller="value-flash" data-value-flash-timestamp-value="${timestamp}"><span class="inline-block">1.2 kW</span></td></tr></tbody></table>`;
    app = Application.start();
    app.register('value-flash', ValueFlashController);
  }

  function cell() {
    return document.querySelector<HTMLElement>(
      '[data-controller="value-flash"]',
    )!;
  }

  // Mutate the attribute the way a Turbo morph would; Stimulus picks it up
  // asynchronously via its MutationObserver.
  async function setTimestamp(timestamp: string) {
    cell().setAttribute('data-value-flash-timestamp-value', timestamp);
    await tick();
  }

  it('does not animate on the initial render', async () => {
    start('2026-06-13T07:00:00Z');
    await tick();

    expect(animateSpy).not.toHaveBeenCalled();
  });

  it('does not animate when an empty cell is first populated', async () => {
    // Hard reload: cells render without a reading, then the first poll fills
    // them in. That is not a "newer value", so it must stay still.
    start('');
    await tick();

    await setTimestamp('2026-06-13T07:00:00Z');

    expect(animateSpy).not.toHaveBeenCalled();
  });

  it('does not animate when a value disappears', async () => {
    start('2026-06-13T07:00:00Z');
    await tick();

    await setTimestamp('');

    expect(animateSpy).not.toHaveBeenCalled();
  });

  it('animates when the timestamp advances', async () => {
    start('2026-06-13T07:00:00Z');
    await tick();

    await setTimestamp('2026-06-13T07:01:00Z');
    await setTimestamp('2026-06-13T07:02:00Z');

    expect(animateSpy).toHaveBeenCalledTimes(2);
  });

  it('does not animate when the timestamp is unchanged', async () => {
    start('2026-06-13T07:00:00Z');
    await tick();

    // Same value re-applied: no attribute mutation, no flash.
    await setTimestamp('2026-06-13T07:00:00Z');

    expect(animateSpy).not.toHaveBeenCalled();
  });

  it('respects prefers-reduced-motion', async () => {
    vi.spyOn(window, 'matchMedia').mockReturnValue({
      matches: true,
    } as MediaQueryList);
    start('2026-06-13T07:00:00Z');
    await tick();

    await setTimestamp('2026-06-13T07:01:00Z');

    expect(animateSpy).not.toHaveBeenCalled();
  });
});
