import { Controller } from '@hotwired/stimulus';
import ServiceRowComponentController from '../service_row/component_controller';

export default class extends Controller {
  static targets = ['startButton', 'stopButton', 'restartButton'];
  static outlets = ['service-row--component'];

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare restartButtonTarget: HTMLButtonElement;
  declare serviceRowComponentOutlets: ServiceRowComponentController[];

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
    this.restartButtonTarget.disabled = canStop.length === 0;
  }

  async startAll() {
    for (const outlet of this.serviceRowComponentOutlets.filter(
      (o) => o.canStart,
    )) {
      await outlet.start();
    }
  }

  async stopAll() {
    for (const outlet of this.serviceRowComponentOutlets.filter(
      (o) => o.canStop,
    )) {
      await outlet.stop();
    }
  }

  async restartAll() {
    for (const outlet of this.serviceRowComponentOutlets.filter(
      (o) => o.canStop,
    )) {
      await outlet.restart();
    }
  }
}
