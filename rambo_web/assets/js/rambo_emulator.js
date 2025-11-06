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
    this.romStagingView = null;
    this.heapBase = 0;
    this.heapLimit = 0;
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

    // Create WebAssembly memory (256MB max, 16MB initial = 256 pages)
    const memory = new WebAssembly.Memory({
      initial: 256,  // 256 pages * 64KB = 16MB
      maximum: 4096  // 4096 pages * 64KB = 256MB
    });

    // Import memory into WASM module
    const { instance } = await WebAssembly.instantiate(bytes, {
      env: { memory }
    });

    this.instance = instance;
    this.exports = instance.exports;
    this.memory = memory;

    const heapBaseGlobal = this.exports.__heap_base;
    const heapBaseValue =
      heapBaseGlobal && typeof heapBaseGlobal === "object" && "value" in heapBaseGlobal
        ? heapBaseGlobal.value
        : heapBaseGlobal;
    const numericBase = typeof heapBaseValue === "bigint"
      ? Number(heapBaseValue)
      : Number(heapBaseValue ?? 0);
    this.heapBase = Number.isFinite(numericBase) ? numericBase : 0;
    this.heapLimit = this.memory.buffer.byteLength;

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
    // Always use fresh buffer reference in case memory grew
    const freshBuffer = this.memory.buffer;
    if (!this.frameBuffer || this.frameBuffer.buffer !== freshBuffer) {
      this.frameBuffer = new Uint8ClampedArray(
        freshBuffer,
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

    const heapMetric = this.exports.rambo_heap_size_bytes ? () => this.exports.rambo_heap_size_bytes() : () => this.memory ? this.memory.buffer.byteLength : 0;
    const beforeHeap = heapMetric();

    const ptr = this.exports.rambo_alloc(bytes.length);
    if (ptr === 0) {
      throw new Error("Failed to allocate ROM buffer");
    }

    const afterHeap = heapMetric();
    const lastPtr = this.exports.rambo_last_alloc_ptr ? this.exports.rambo_last_alloc_ptr() : ptr;
    const lastSize = this.exports.rambo_last_alloc_size ? this.exports.rambo_last_alloc_size() : bytes.length;
    console.debug(
      "[RAMBO] wasm alloc",
      { request: bytes.length, ptr, heapBefore: beforeHeap, heapAfter: afterHeap, lastPtr, lastSize }
    );

    // CRITICAL: Use fresh buffer reference after allocation (memory may have grown)
    // With imported memory, this.memory is the source of truth (not exports)
    const freshBuffer = this.memory.buffer;
    const heapBytes = freshBuffer.byteLength;
    const end = ptr + bytes.length;
    if (ptr < (this.heapBase ?? 0)) {
      this.exports.rambo_free(ptr, bytes.length);
      throw new Error(
        `ROM allocation (${ptr}) is below heap base ${(this.heapBase ?? 0)}`
      );
    }
    if (end > heapBytes) {
      this.exports.rambo_free(ptr, bytes.length);
      throw new Error(
        `ROM copy exceeds heap bounds (ptr=${ptr}, len=${bytes.length}, heap=${heapBytes})`
      );
    }

    this.heapLimit = heapBytes;
    this.romStagingView = new Uint8Array(freshBuffer, ptr, bytes.length);
    this.romStagingView.set(bytes);

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
    this.romStagingView = null;
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
