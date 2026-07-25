import {
  describe,
  it,
  expect,
  beforeAll,
  beforeEach,
  afterEach,
  vi,
} from 'vitest';
import type { FrameElement } from '@hotwired/turbo';
import { reloadFrame, startFrameRecovery } from '@/utils/frame_recovery';

// Turbo isn't running in these specs, so <turbo-frame> is an unknown element.
// We stub the one method we call on it and set the `complete` attribute Turbo
// would set by hand.
function createFrame(src = '/services/dashboard/row') {
  const frame = document.createElement('turbo-frame') as FrameElement;
  frame.setAttribute('src', src);
  frame.setAttribute('loading', 'lazy');
  frame.dataset.src = src;

  const reload = vi.fn();
  Object.assign(frame, { reload });
  document.body.appendChild(frame);

  return { frame, reload };
}

function failFetch(frame: Element) {
  frame.dispatchEvent(
    new CustomEvent('turbo:fetch-request-error', { bubbles: true }),
  );
}

describe('frame_recovery', () => {
  describe('reloadFrame', () => {
    it('switches a frame that never loaded to eager to force a load', () => {
      const { frame, reload } = createFrame();

      reloadFrame(frame);

      expect(frame.getAttribute('loading')).toBe('eager');
      // reload() would be a no-op for a frame that never completed a load
      expect(reload).not.toHaveBeenCalled();
    });

    it('reloads a frame that already completed a load', () => {
      const { frame, reload } = createFrame();
      frame.setAttribute('complete', '');

      reloadFrame(frame);

      expect(reload).toHaveBeenCalledOnce();
      expect(frame.getAttribute('loading')).toBe('lazy');
    });

    it('leaves an unchanged src alone, which would clear `complete`', () => {
      const { frame } = createFrame();
      frame.setAttribute('complete', '');
      const setAttribute = vi.spyOn(frame, 'setAttribute');

      reloadFrame(frame);

      expect(setAttribute).not.toHaveBeenCalledWith('src', expect.anything());
    });

    it('restores a missing src from data-src', () => {
      const { frame } = createFrame();
      frame.removeAttribute('src');

      reloadFrame(frame);

      expect(frame.getAttribute('src')).toBe('/services/dashboard/row');
      expect(frame.getAttribute('loading')).toBe('eager');
    });
  });

  describe('startFrameRecovery', () => {
    beforeAll(() => startFrameRecovery());

    beforeEach(() => {
      vi.useFakeTimers();
      document.body.innerHTML = '';
    });

    afterEach(() => {
      vi.clearAllTimers();
      vi.useRealTimers();
    });

    it('retries a frame whose fetch errored', () => {
      const { frame } = createFrame();

      failFetch(frame);
      expect(frame.getAttribute('loading')).toBe('lazy');

      vi.advanceTimersByTime(3_000);
      expect(frame.getAttribute('loading')).toBe('eager');
    });

    it('skips the retry when the frame loaded in the meantime', () => {
      const { frame } = createFrame();

      failFetch(frame);
      frame.setAttribute('complete', '');
      vi.advanceTimersByTime(3_000);

      expect(frame.getAttribute('loading')).toBe('lazy');
    });

    it('backs off and gives up after the configured attempts', () => {
      const { frame } = createFrame();

      // 3 delays are configured; each retry fails again
      for (let i = 0; i < 3; i++) {
        failFetch(frame);
        vi.advanceTimersByTime(30_000);
        frame.setAttribute('loading', 'lazy');
      }

      failFetch(frame);
      vi.advanceTimersByTime(60_000);

      expect(frame.getAttribute('loading')).toBe('lazy');
    });
  });
});
