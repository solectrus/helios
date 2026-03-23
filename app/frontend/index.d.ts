// ActionCable type declarations
declare module '@rails/actioncable' {
  export interface Subscription {
    unsubscribe(): void;
    perform(action: string, data?: object): void;
  }

  interface CreateMixin {
    create(
      channelName: string | object,
      mixin?: {
        connected?: () => void;
        disconnected?: () => void;
        received?: (data: unknown) => void;
        [key: string]: unknown;
      },
    ): Subscription;
  }

  export interface Consumer {
    subscriptions: CreateMixin;
  }

  export function createConsumer(url?: string): Consumer;
}

// Dummy declaration for Turbo 8
declare module '@hotwired/turbo' {
  export class FrameElement extends HTMLElement {
    src: string | undefined;
    reload(): Promise<void>;
  }

  export type TurboFrameMissingEvent = CustomEvent<{
    response: Response;
  }>;

  interface StreamActionContext {
    hasAttribute(attributeName: string): boolean;
    templateContent: DocumentFragment;
    templateElement: HTMLTemplateElement;
    targetElements: Element[];
  }

  export function visit(url: string, options?): void;
  export function renderStreamMessage(html: string): void;

  export const StreamActions: {
    [key: string]: (this: Element) => void;
  };
}
