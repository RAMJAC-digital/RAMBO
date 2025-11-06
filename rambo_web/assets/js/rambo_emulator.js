const NES_WIDTH = 256;
const NES_HEIGHT = 240;
const FRAME_PIXELS = NES_WIDTH * NES_HEIGHT;

const KEY_BINDINGS = new Map([
  ["ArrowUp", 1 << 4],
  ["ArrowDown", 1 << 5],
  ["ArrowLeft", 1 << 6],
  ["ArrowRight", 1 << 7],
  ["KeyX", 1 << 0], // A
  ["KeyZ", 1 << 1], // B
  ["Enter", 1 << 3], // Start
  ["ShiftLeft", 1 << 2], // Select
  ["ShiftRight", 1 << 2]
]);

export class RamboEmulatorClient {
  constructor(wasmPath) {
    this.wasmPath = wasmPath;
    this.readyPromise = null;
    this.instance = null;
    this.exports = null;
    this.memory = null;
    this.canvas = null;
    this.ctx = null;
    this.imageData = null;
    this.framePtr = 0;
    this.framePixels = FRAME_PIXELS;
    this.frameBuffer = null;
    this.controllerMask = 0;
    this.running = false;
    this.animationHandle = null;
    this.raf = (timestamp) => this.renderLoop(timestamp);
  }

  setWasmPath(path) {
    if (path && path !== this.wasmPath) {
      this.wasmPath = path;
      this.readyPromise = null;
      this.instance = null;
      this.exports = null;
      this.memory = null;
    }
  }

  async ensureReady() {
    if (!this.readyPromise) {
      this.readyPromise = this.loadModule();
    }
    return this.readyPromise;
  }

  async loadModule() {
    const response = await fetch(this.wasmPath);
    if (!response.ok) {
      throw new Error(`Failed to fetch wasm module (${response.status})`);
    }
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, {});
    this.instance = instance;
    this.exports = instance.exports;
    this.memory = this.exports.memory;
    return this;
  }

  attachCanvas(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d", { alpha: false });
    this.canvas.width = NES_WIDTH;
    this.canvas.height = NES_HEIGHT;
    this.imageData = new ImageData(NES_WIDTH, NES_HEIGHT);
    this.clearCanvas();
  }

  detachCanvas() {
    this.stopLoop();
    this.canvas = null;
    this.ctx = null;
    this.imageData = null;
  }

  getFrameBuffer() {
    if (!this.memory) {
      return null;
    }
    if (!this.frameBuffer || this.frameBuffer.buffer !== this.memory.buffer) {
      this.frameBuffer = new Uint8ClampedArray(
        this.memory.buffer,
        this.framePtr,
        this.framePixels * 4
      );
    }
    return this.frameBuffer;
  }

  stopLoop() {
    this.running = false;
    if (this.animationHandle) {
      cancelAnimationFrame(this.animationHandle);
      this.animationHandle = null;
    }
  }

  startLoop() {
    if (!this.running) {
      this.running = true;
      this.animationHandle = requestAnimationFrame(this.raf);
    }
  }

  renderLoop() {
    if (!this.running) {
      return;
    }
    try {
      const result = this.exports.rambo_step_frame();
      if (result !== 0) {
        console.error("rambo_step_frame returned error", result);
        this.stopLoop();
        return;
      }
      this.drawFrame();
    } finally {
      if (this.running) {
        this.animationHandle = requestAnimationFrame(this.raf);
      }
    }
  }

  drawFrame() {
    if (!this.ctx || !this.imageData) {
      return;
    }
    const buffer = this.getFrameBuffer();
    if (!buffer) {
      return;
    }
    this.imageData.data.set(buffer);
    this.ctx.putImageData(this.imageData, 0, 0);
  }

  clearCanvas() {
    if (this.ctx && this.canvas) {
      this.ctx.fillStyle = "#000000";
      this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    }
  }

  async loadRom(bytes) {
    if (!bytes || bytes.length === 0) {
      throw new Error("ROM is empty");
    }
    await this.ensureReady();

    const ptr = this.exports.rambo_alloc(bytes.length);
    if (ptr === 0) {
      throw new Error("Failed to allocate ROM buffer");
    }
    const wasmView = new Uint8Array(this.memory.buffer, ptr, bytes.length);
    wasmView.set(bytes);

    const result = this.exports.rambo_init(ptr, bytes.length);
    this.exports.rambo_free(ptr, bytes.length);

    if (result !== 0) {
      throw new Error(`RAMBO init failed (code ${result})`);
    }

    this.framePtr = this.exports.rambo_framebuffer_ptr();
    this.framePixels = this.exports.rambo_framebuffer_size();
    this.frameBuffer = null;
    this.controllerMask = 0;
    this.exports.rambo_set_controller_state(0, this.controllerMask);
    this.startLoop();
  }

  pause() {
    this.stopLoop();
  }

  resume() {
    if (this.memory && this.framePtr !== 0) {
      this.startLoop();
    }
  }

  reset() {
    if (!this.exports) return;
    this.exports.rambo_reset();
    this.controllerMask = 0;
    this.exports.rambo_set_controller_state(0, this.controllerMask);
    this.drawFrame();
  }

  shutdown() {
    if (!this.exports) return;
    this.stopLoop();
    this.exports.rambo_shutdown();
    this.controllerMask = 0;
    this.framePtr = 0;
    this.frameBuffer = null;
    this.clearCanvas();
  }

  updateButtonMask(mask, pressed) {
    if (pressed) {
      this.controllerMask |= mask;
    } else {
      this.controllerMask &= ~mask;
    }
    this.exports.rambo_set_controller_state(0, this.controllerMask);
  }

  handleKey(code, pressed) {
    const mask = KEY_BINDINGS.get(code);
    if (!mask) {
      return false;
    }
    this.updateButtonMask(mask, pressed);
    return true;
  }
}
