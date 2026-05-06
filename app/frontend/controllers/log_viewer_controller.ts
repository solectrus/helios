import { Controller } from '@hotwired/stimulus';
import consumer from '../channels/consumer';
import type { Subscription } from '@rails/actioncable';

export default class LogViewerController extends Controller {
  static targets = [
    'output',
    'scrollContainer',
    'status',
    'loader',
    'newLines',
  ];
  static values = {
    service: String,
    streaming: { type: String, default: 'connecting' },
  };

  declare outputTarget: HTMLPreElement;
  declare scrollContainerTarget: HTMLElement;
  declare loaderTarget: HTMLElement;
  declare hasLoaderTarget: boolean;
  declare statusTarget: HTMLElement;
  declare hasStatusTarget: boolean;
  declare newLinesTarget: HTMLButtonElement;
  declare hasNewLinesTarget: boolean;
  declare serviceValue: string;
  declare streamingValue: 'connecting' | 'connected' | 'disconnected';

  private static readonly MAX_LINES = 5000;

  private subscription?: Subscription;
  private isScrolledToBottom = true;
  private isLoadingOlder = false;
  private hasMoreLogs = true;
  private initialScrollDone = false;
  private isAutoScrolling = false;
  private autoScrollTimer?: number;
  private resizeObserver?: ResizeObserver;
  private prefersReducedMotion = false;
  private scrollFrame?: number;

  connect() {
    this.prefersReducedMotion = window.matchMedia(
      '(prefers-reduced-motion: reduce)',
    ).matches;

    // The container has zero size until the surrounding <dialog> opens via
    // showModal(), which happens after Stimulus connect(). Observe size to
    // trigger the initial scroll-to-bottom once the dialog is visible.
    this.resizeObserver = new ResizeObserver(() => this.handleResize());
    this.resizeObserver.observe(this.scrollContainerTarget);
    this.scrollContainerTarget.addEventListener('scroll', this.handleScroll);
    this.scrollContainerTarget.addEventListener(
      'scrollend',
      this.handleScrollEnd,
    );
    this.subscribe();
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    this.resizeObserver = undefined;
    clearTimeout(this.autoScrollTimer);
    if (this.scrollFrame !== undefined) {
      cancelAnimationFrame(this.scrollFrame);
      this.scrollFrame = undefined;
    }
    this.scrollContainerTarget.removeEventListener('scroll', this.handleScroll);
    this.scrollContainerTarget.removeEventListener(
      'scrollend',
      this.handleScrollEnd,
    );
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

  streamingValueChanged() {
    if (!this.hasStatusTarget) return;

    this.statusTarget.dataset.state = this.streamingValue;
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
          this.streamingValue = 'connected';
        },
        disconnected: () => {
          this.streamingValue = 'disconnected';
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

    if (!this.prefersReducedMotion) {
      el.classList.add('log-line-enter');
      el.addEventListener(
        'animationend',
        () => el.classList.remove('log-line-enter'),
        { once: true },
      );
    }

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
      this.scrollToBottom({ smooth: true });
    } else {
      this.showNewLinesIndicator(true);
    }
  }

  followBottom() {
    this.showNewLinesIndicator(false);
    this.scrollToBottom({ smooth: true });
  }

  private showNewLinesIndicator(visible: boolean) {
    if (!this.hasNewLinesTarget) return;
    this.newLinesTarget.classList.toggle('hidden', !visible);
  }

  private scrollToBottom({ smooth = false }: { smooth?: boolean } = {}) {
    // Treat any auto-scroll as an intent to follow. Without this, clicking the
    // "new lines" button would smooth-scroll down but leave isScrolledToBottom
    // false, because handleScroll is gated by isAutoScrolling during the scroll.
    this.isScrolledToBottom = true;
    if (smooth) {
      // Suppress isScrolledToBottom updates while the smooth scroll runs;
      // intermediate scroll events would otherwise mark us as "not at bottom"
      // and break auto-follow on the next incoming line. scrollend resets it;
      // the timer is a fallback for browsers without scrollend (Safari < 18.2)
      // and bursts that cancel the scroll mid-flight, where scrollend may
      // never fire and would leave isAutoScrolling stuck at true.
      this.isAutoScrolling = true;
      clearTimeout(this.autoScrollTimer);
      this.autoScrollTimer = window.setTimeout(() => {
        this.isAutoScrolling = false;
      }, 1000);
    }
    this.scrollContainerTarget.scrollTo({
      top: this.scrollContainerTarget.scrollHeight,
      behavior: smooth ? 'smooth' : 'instant',
    });
  }

  private handleScroll = () => {
    // Coalesce bursts of scroll events into one read per frame; the geometry
    // math is cheap, but smooth-scroll fires per-frame and we don't need to
    // re-evaluate more often than the browser repaints.
    if (this.scrollFrame !== undefined) return;
    this.scrollFrame = requestAnimationFrame(() => {
      this.scrollFrame = undefined;

      const { scrollTop, scrollHeight, clientHeight } =
        this.scrollContainerTarget;

      if (!this.isAutoScrolling) {
        this.isScrolledToBottom = scrollHeight - scrollTop - clientHeight < 20;
        if (this.isScrolledToBottom) {
          this.showNewLinesIndicator(false);
        }
      }

      if (scrollTop < 50 && !this.isLoadingOlder && this.hasMoreLogs) {
        this.fetchOlderLogs();
      }
    });
  };

  private handleScrollEnd = () => {
    this.isAutoScrolling = false;
    clearTimeout(this.autoScrollTimer);
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
    if (!this.hasLoaderTarget) return;
    this.loaderTarget.classList.toggle('hidden', !visible);
  }
}
