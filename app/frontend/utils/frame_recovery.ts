import type { FrameElement } from '@hotwired/turbo';

const RETRY_DELAYS = [3_000, 10_000, 30_000];

// Force a (re)load, whatever state Turbo left the frame in.
export function reloadFrame(frame: FrameElement) {
  const src = frame.getAttribute('src') ?? frame.dataset.src;
  if (!src) return;

  // Read `complete` first and only touch `src` when it actually differs:
  // assigning it makes Turbo drop `complete`, which would hide from us that
  // this frame ever loaded.
  const loadedBefore = frame.hasAttribute('complete');
  if (frame.getAttribute('src') !== src) frame.setAttribute('src', src);

  if (loadedBefore) {
    frame.reload();
  } else {
    // A frame that never completed a load ignores both `reload()` and a fresh
    // `src`: Turbo's `sourceURLChanged` only loads for eager frames or frames
    // that loaded before. Changing the loading style is the trigger left.
    frame.setAttribute('loading', 'eager');
  }
}

// Turbo gives a lazy frame exactly one chance to load: `#loadSourceURL()` stops
// its IntersectionObserver as soon as the first fetch starts, and nothing
// retries afterwards. So a frame whose fetch fails — the browser restoring tabs
// after a reboot, before the host is reachable — keeps its skeleton placeholder
// (an endless spinner) until the user reloads the page by hand.
export function startFrameRecovery() {
  document.addEventListener('turbo:fetch-request-error', ({ target }) => {
    if (!(target instanceof HTMLElement) || target.localName !== 'turbo-frame')
      return;

    const frame = target as FrameElement;
    const attempt = Number(frame.dataset.retryAttempt ?? 0);
    const delay = RETRY_DELAYS[attempt];
    if (delay === undefined) return; // Out of retries, leave it to the user

    frame.dataset.retryAttempt = String(attempt + 1);
    setTimeout(() => {
      if (!frame.hasAttribute('complete')) reloadFrame(frame);
    }, delay);
  });
}
