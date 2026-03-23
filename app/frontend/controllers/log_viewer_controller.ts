import { Controller } from '@hotwired/stimulus';
import consumer from '../channels/consumer';
import type { Subscription } from '@rails/actioncable';

export default class LogViewerController extends Controller {
  static targets = ['output', 'streamingDot', 'streamingLabel'];
  static values = {
    service: String,
  };

  declare outputTarget: HTMLPreElement;
  declare streamingDotTarget: HTMLElement;
  declare streamingLabelTarget: HTMLElement;
  declare hasStreamingDotTarget: boolean;
  declare hasStreamingLabelTarget: boolean;
  declare serviceValue: string;

  private static readonly MAX_LINES = 5000;

  private subscription?: Subscription;
  private isScrolledToBottom = true;

  connect() {
    this.scrollToBottom();
    this.outputTarget.addEventListener('scroll', this.handleScroll);
    this.subscribe();
  }

  disconnect() {
    this.outputTarget.removeEventListener('scroll', this.handleScroll);
    this.unsubscribe();
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

    while (children.length > LogViewerController.MAX_LINES) {
      children[0].remove();
    }

    if (this.isScrolledToBottom) this.scrollToBottom();
  }

  private scrollToBottom() {
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight;
  }

  private handleScroll = () => {
    const { scrollTop, scrollHeight, clientHeight } = this.outputTarget;
    this.isScrolledToBottom = scrollHeight - scrollTop - clientHeight < 20;
  };

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
