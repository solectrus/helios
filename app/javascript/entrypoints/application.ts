import '@hotwired/turbo-rails';
import.meta.glob('../channels/**/*_channel.{js,ts}', { eager: true });

import '@/utils/setupStimulus';
