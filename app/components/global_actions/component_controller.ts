import { Controller } from '@hotwired/stimulus';
import ServiceRowComponentController from '../service_row/component_controller';

export default class extends Controller {
  static targets = ['startButton', 'stopButton'];
  static outlets = ['service-row--component'];

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare serviceRowComponentOutlets: ServiceRowComponentController[];

  connect() {
    // Listen for Turbo frame loads to update buttons after lazy loading completes
    document.addEventListener('turbo:frame-load', this.handleFrameLoad);
  }

  disconnect() {
    document.removeEventListener('turbo:frame-load', this.handleFrameLoad);
  }

  private handleFrameLoad = () => {
    this.updateButtons();
  };

  serviceRowComponentOutletConnected() {
    this.updateButtons();
  }

  serviceRowComponentOutletDisconnected() {
    this.updateButtons();
  }

  updateButtons() {
    const canStart = this.serviceRowComponentOutlets.some(
      (outlet) => outlet.canStart,
    );
    const canStop = this.serviceRowComponentOutlets.some(
      (outlet) => outlet.canStop,
    );

    this.startButtonTarget.classList.toggle('hidden', !canStart);
    this.stopButtonTarget.classList.toggle('hidden', !canStop);
  }
}
