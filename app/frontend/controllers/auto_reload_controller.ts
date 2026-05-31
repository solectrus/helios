import PollingController from '../utils/pollingController';

// Periodically refreshes the closest Turbo Frame by fetching `urlValue` and
// replacing the frame element in place. We avoid setting `src` on the frame
// directly because Turbo would eagerly re-fetch on initial page load and
// flash the already-rendered content. The controller must live *inside* the
// frame, so that when the next response no longer needs polling, this
// element is gone and the controller disconnects automatically.
export default class extends PollingController {
  static values = {
    ...PollingController.values,
    interval: { type: Number, default: 3000 },
    url: String,
  };

  declare urlValue: string;

  private abortController: AbortController | null = null;

  disconnect() {
    super.disconnect();
    this.abortController?.abort();
  }

  protected async refresh() {
    const frame = this.element.closest('turbo-frame');
    if (!frame) return;

    this.abortController?.abort();
    this.abortController = new AbortController();
    const { signal } = this.abortController;

    try {
      // Send the Turbo-Frame header so the server treats this poll as a frame
      // request for this exact frame. Pages that lazy-load their body keyed on
      // that header (e.g. backups) then return the real content here, not the
      // shell's skeleton placeholder.
      const response = await fetch(this.urlValue, {
        headers: { Accept: 'text/html', 'Turbo-Frame': frame.id },
        signal,
      });
      if (!response.ok) return;

      const html = await response.text();
      const newFrame = new DOMParser()
        .parseFromString(html, 'text/html')
        .querySelector(`turbo-frame#${CSS.escape(frame.id)}`);
      if (!newFrame) return;

      // Skip the swap when nothing changed — avoids per-tick flicker, focus
      // loss, scroll resets, and Stimulus disconnect/reconnect storms.
      if (newFrame.innerHTML === frame.innerHTML) return;

      frame.replaceWith(newFrame);
    } catch {
      // Silently ignore network errors and aborts during polling.
    }
  }
}
