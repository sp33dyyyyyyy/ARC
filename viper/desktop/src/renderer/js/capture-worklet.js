// AudioWorklet: forwards mono PCM frames from the microphone to the main thread.
class ViperCapture extends AudioWorkletProcessor {
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (ch) this.port.postMessage(ch.slice(0));
    return true;
  }
}
registerProcessor('viper-capture', ViperCapture);
