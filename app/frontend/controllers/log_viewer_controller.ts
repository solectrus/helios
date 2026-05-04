import { Controller } from '@hotwired/stimulus';
import consumer from '../channels/consumer';
import type { Subscription } from '@rails/actioncable';

export default class LogViewerController extends Controller {
  static targets = [
    'output',
    'scrollContainer',
    'streamingDot',
    'streamingLabel',
    'loader',
  ];
  static values = {
    service: String,
  };

  declare outputTarget: HTMLPreElement;
  declare scrollContainerTarget: HTMLElement;
  declare loaderTarget: HTMLElement;
  declare hasLoaderTarget: boolean;
  declare streamingDotTarget: HTMLElement;
  declare streamingLabelTarget: HTMLElement;
  declare hasStreamingDotTarget: boolean;
  declare hasStreamingLabelTarget: boolean;
  declare serviceValue: string;

  private static readonly MAX_LINES = 5000;

  private subscription?: Subscription;
  private isScrolledToBottom = true;
  private isLoadingOlder = false;
  private hasMoreLogs = true;
  private initialScrollDone = false;
  private resizeObserver?: ResizeObserver;

  connect() {
    // The container has zero size until the surrounding <dialog> opens via
    // showModal(), which happens after Stimulus connect(). Observe size to
    // trigger the initial scroll-to-bottom once the dialog is visible.
    this.resizeObserver = new ResizeObserver(() => this.handleResize());
    this.resizeObserver.observe(this.scrollContainerTarget);
    this.scrollContainerTarget.addEventListener('scroll', this.handleScroll);
    this.subscribe();
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    this.resizeObserver = undefined;
    this.scrollContainerTarget.removeEventListener('scroll', this.handleScroll);
    this.unsubscribe();
  }

  private handleResize() {
    if (
      !this.initialScrollDone &&
      this.scrollContainerTarget.scrollHeight > 0
    ) {
      this.initialScrollDone = true;
      this.scrollToBottom();
    }
  }

  private subscribe() {
    this.subscription = consumer.subscriptions.create(
      { channel: 'LogsChannel', service: this.serviceValue },
      {
        received: (data: unknown) => {
          const { html } = data as { html: string };
          this.insertLine(html);
        },
        connected: () => {
          this.setStreamingStatus(true);
        },
        disconnected: () => {
          this.setStreamingStatus(false);
        },
      },
    );
  }

  private unsubscribe() {
    this.subscription?.unsubscribe();
    this.subscription = undefined;
  }

  private insertLine(html: string) {
    const temp = document.createElement('template');
    temp.innerHTML = html;
    const el = temp.content.firstElementChild as HTMLElement | null;
    if (!el) return;

    const ts = el.dataset.ts;
    const children = this.outputTarget.children;

    if (!ts || children.length === 0) {
      this.outputTarget.appendChild(el);
    } else {
      let inserted = false;
      for (let i = children.length - 1; i >= 0; i--) {
        const childTs = (children[i] as HTMLElement).dataset.ts;
        if (childTs && childTs <= ts) {
          children[i].after(el);
          inserted = true;
          break;
        }
      }
      if (!inserted) {
        this.outputTarget.prepend(el);
      }
    }

    if (this.isScrolledToBottom) {
      while (children.length > LogViewerController.MAX_LINES) {
        children[0].remove();
      }
      this.scrollToBottom();
    }
  }

  private scrollToBottom() {
    this.scrollContainerTarget.scrollTop =
      this.scrollContainerTarget.scrollHeight;
  }

  private handleScroll = () => {
    const { scrollTop, scrollHeight, clientHeight } =
      this.scrollContainerTarget;
    this.isScrolledToBottom = scrollHeight - scrollTop - clientHeight < 20;

    if (scrollTop < 50 && !this.isLoadingOlder && this.hasMoreLogs) {
      this.fetchOlderLogs();
    }
  };

  private getOldestTimestamp(): string | null {
    const firstTimestamped = this.outputTarget.querySelector(
      '[data-ts]',
    ) as HTMLElement | null;
    return firstTimestamped?.dataset.ts ?? null;
  }

  private async fetchOlderLogs() {
    const oldest = this.getOldestTimestamp();
    if (!oldest) return;

    this.isLoadingOlder = true;
    this.showLoader(true);

    try {
      const url = `/services/${encodeURIComponent(this.serviceValue)}/log?until=${encodeURIComponent(oldest)}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const html = await response.text();
      if (!html.trim()) {
        this.hasMoreLogs = false;
        return;
      }

      const prevScrollHeight = this.scrollContainerTarget.scrollHeight;

      const temp = document.createElement('template');
      temp.innerHTML = html;
      const fragment = temp.content;

      // Docker --until is inclusive, so remove lines at the boundary to prevent duplicates
      fragment.querySelectorAll('[data-ts]').forEach((el) => {
        if ((el as HTMLElement).dataset.ts! >= oldest) el.remove();
      });

      if (!fragment.children.length) {
        this.hasMoreLogs = false;
        return;
      }

      this.outputTarget.prepend(fragment);

      // If oldest timestamp didn't change, we've reached the beginning
      if (this.getOldestTimestamp() === oldest) {
        this.hasMoreLogs = false;
      }

      // Restore scroll position
      const newScrollHeight = this.scrollContainerTarget.scrollHeight;
      this.scrollContainerTarget.scrollTop +=
        newScrollHeight - prevScrollHeight;

      // Trim oldest lines from bottom if exceeding limit
      const children = this.outputTarget.children;
      while (children.length > LogViewerController.MAX_LINES) {
        children[children.length - 1].remove();
      }
    } catch (e) {
      console.error('Failed to load older logs:', e);
    } finally {
      this.isLoadingOlder = false;
      this.showLoader(false);
    }
  }

  private showLoader(visible: boolean) {
    if (this.hasLoaderTarget) {
      this.loaderTarget.classList.toggle('hidden', !visible);
    }
  }

  private setStreamingStatus(connected: boolean) {
    if (!this.hasStreamingDotTarget || !this.hasStreamingLabelTarget) return;

    const dot = this.streamingDotTarget;
    const label = this.streamingLabelTarget;

    if (connected) {
      dot.className = 'relative mr-2 flex h-2 w-2';
      dot.innerHTML =
        '<span class="absolute h-full w-full animate-ping rounded-full bg-success/75"></span>' +
        '<span class="h-2 w-2 rounded-full bg-success"></span>';
      label.textContent = 'Live';
      label.className = 'text-success';
    } else {
      dot.className = 'mr-2 inline-block h-2 w-2 rounded-full bg-error';
      dot.innerHTML = '';
      label.textContent = 'Disconnected';
      label.className = 'text-error';
    }
  }
}
