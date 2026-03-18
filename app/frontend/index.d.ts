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
