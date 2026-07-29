import { describe, it, expect, afterEach, vi } from 'vitest';
import { Application } from '@hotwired/stimulus';
import ServiceRowComponentController from '@components/service_row/component_controller';

const SRC = '/services/power-splitter/row';

function tick() {
  return new Promise((resolve) => queueMicrotask(resolve));
}

function row(recalculating: boolean) {
  return `
    <div data-controller="service-row--component"
         data-service-row--component-name-value="power-splitter"
         data-service-row--component-status-value="running"
         data-service-row--component-recalculating-value="${recalculating}"
         data-service-row--component-interval-value="1000"></div>`;
}

describe('ServiceRowComponentController', () => {
  let app: Application;

  afterEach(() => {
    app?.stop();
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  async function start(recalculating: boolean) {
    vi.useFakeTimers();
    document.body.innerHTML = `<turbo-frame id="service-power-splitter" data-src="${SRC}">${row(recalculating)}</turbo-frame>`;

    app = Application.start();
    app.register('service-row--component', ServiceRowComponentController);
    await tick();

    return document.querySelector('turbo-frame') as HTMLElement;
  }

  it('reloads the enclosing frame while a recalculation is running', async () => {
    const frame = await start(true);

    vi.advanceTimersByTime(1000);

    expect(frame.getAttribute('src')).toBe(SRC);
  });

  it('leaves the frame alone while the service is idle', async () => {
    const frame = await start(false);

    vi.advanceTimersByTime(5000);

    expect(frame.getAttribute('src')).toBeNull();
  });

  // The regression this guards: with the controller mounted on the frame
  // itself, a reload would swap the children but keep the frame's stale
  // values, so the poll could never learn that it is done.
  it('stops polling once the reloaded row reports the recalculation as over', async () => {
    const frame = await start(true);

    vi.advanceTimersByTime(1000);
    expect(frame.getAttribute('src')).toBe(SRC);

    // What Turbo does on a frame reload: replace the frame's children.
    frame.removeAttribute('src');
    frame.innerHTML = row(false);
    await tick();

    vi.advanceTimersByTime(5000);

    expect(frame.getAttribute('src')).toBeNull();
  });
});
