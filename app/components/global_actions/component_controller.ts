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
    const canStart = this.serviceRowComponentOutlets.filter(
      (outlet) => outlet.canStart,
    );
    const canStop = this.serviceRowComponentOutlets.filter(
      (outlet) => outlet.canStop,
    );

    this.startButtonTarget.disabled = canStart.length === 0;
    this.stopButtonTarget.disabled = canStop.length === 0;
  }
}
