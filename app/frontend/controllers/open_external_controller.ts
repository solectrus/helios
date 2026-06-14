import { Controller } from '@hotwired/stimulus';

// Opens a service in a new browser tab. An absolute URL (e.g. a dashboard
// behind a managed Traefik) takes precedence; otherwise a host-port URL is
// built at the hostname HELIOS is currently accessed from, so it works
// regardless of how HELIOS itself is reached.
//
// Wire up via either data-url or data-port on the element triggering the
// action:
//   data-controller="open-external"
//   data-action="click->open-external#open"
//   data-url="https://dashboard.example.com"   (or data-port="3000")
export default class extends Controller {
  open(event: Event) {
    const target = event.currentTarget as HTMLElement;

    const url = target.dataset.url;
    if (url) {
      window.open(url, '_blank');
      return;
    }

    const port = target.dataset.port;
    if (port) {
      window.open(`http://${window.location.hostname}:${port}`, '_blank');
    }
  }
}
