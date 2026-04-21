import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';
import RelativeTimeController from '@/controllers/relative_time_controller';

function clearPreferencesCookie() {
  document.cookie = 'preferences=; path=/; max-age=0';
}

function tick() {
  // Use microtask to flush Stimulus connect callbacks without relying on
  // setTimeout (which is faked by vi.useFakeTimers).
  return new Promise((resolve) => queueMicrotask(resolve));
}

describe('RelativeTimeController', () => {
  let app: Application;

  beforeEach(() => {
    vi.useFakeTimers();
    clearPreferencesCookie();
    document.documentElement.lang = 'en';
  });

  afterEach(() => {
    app?.stop();
    document.body.innerHTML = '';
    vi.useRealTimers();
  });

  function start(html: string) {
    document.body.innerHTML = html;
    app = Application.start();
    app.register('relative-time', RelativeTimeController);
  }

  it('writes relative text into dataset.tip by default', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T11:59:30Z"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.dataset.tip).toMatch(/30 seconds ago/);
    expect(el.textContent).toBe('');
  });

  it('replaces textContent when target is "text"', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T10:00:00Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toMatch(/2 hours ago/);
  });

  it('uses minutes for values below one hour', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T11:55:00Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toMatch(/5 minutes ago/);
  });

  it('uses days for values above 24 hours', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-18T12:00:00Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toMatch(/3 days ago/);
  });

  it('respects the locale from the preferences cookie', async () => {
    document.cookie = `preferences=${encodeURIComponent('{"locale":"de"}')}; path=/`;
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T11:59:00Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    // German: "vor 1 Minute"
    expect(el.textContent).toMatch(/vor/i);
  });

  it('re-renders when datetime value changes', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T11:59:30Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toMatch(/30 seconds ago/);

    el.dataset.relativeTimeDatetimeValue = '2026-04-21T11:00:00Z';
    await tick();

    expect(el.textContent).toMatch(/1 hour ago/);
  });

  it('does nothing when datetime value is empty', async () => {
    start(
      `<span data-controller="relative-time"
             data-relative-time-target-value="text">initial</span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toBe('initial');
  });

  it('clears the interval on disconnect', async () => {
    vi.setSystemTime(new Date('2026-04-21T12:00:00Z'));
    start(
      `<span data-controller="relative-time"
             data-relative-time-datetime-value="2026-04-21T11:59:00Z"
             data-relative-time-target-value="text"></span>`,
    );
    await tick();

    const el = document.querySelector<HTMLElement>('[data-controller]')!;
    expect(el.textContent).toMatch(/1 minute ago/);

    el.remove();
    await tick();

    vi.setSystemTime(new Date('2026-04-21T13:00:00Z'));
    vi.advanceTimersByTime(60_000);

    // No errors — controller is disconnected and interval cleared
    expect(el.textContent).toMatch(/1 minute ago/);
  });
});
