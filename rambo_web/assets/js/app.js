// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {RamboEmulatorClient} from "./rambo_emulator"

const Hooks = {}
let sharedClient = null

Hooks.RamboEmulator = {
  async mounted() {
    const wasmPath = this.el.dataset.wasmPath
    sharedClient =
      sharedClient === null
        ? new RamboEmulatorClient(wasmPath)
        : (sharedClient.setWasmPath(wasmPath), sharedClient)

    this.client = sharedClient
    this.canvas = this.el.querySelector("#rambo-canvas")
    this.fileInput = this.el.querySelector('input[type="file"]')

    if (!this.canvas || !this.fileInput) {
      console.warn("RamboEmulator hook missing canvas or file input")
      return
    }

    this.client.attachCanvas(this.canvas)

    this.handleFileChange = async (event) => {
      const file = event.target.files?.[0]
      if (!file) {
        return
      }

      try {
        const buffer = await file.arrayBuffer()
        await this.client.loadRom(new Uint8Array(buffer))
        this.pushEvent("rom-loaded", {name: file.name})
      } catch (error) {
        console.error("Failed to load ROM", error)
        this.pushEvent("rom-error", {message: error?.message ?? "Failed to load ROM"})
        this.client.shutdown()
      }
    }

    this.fileInput.addEventListener("change", this.handleFileChange)

    const isInteractiveTarget = (target) =>
      target?.tagName === "INPUT" || target?.tagName === "TEXTAREA" || target?.isContentEditable

    this.handleKeyDown = (event) => {
      if (event.repeat || isInteractiveTarget(event.target)) return
      if (this.client.handleKey(event.code, true)) {
        event.preventDefault()
      }
    }

    this.handleKeyUp = (event) => {
      if (isInteractiveTarget(event.target)) return
      if (this.client.handleKey(event.code, false)) {
        event.preventDefault()
      }
    }

    window.addEventListener("keydown", this.handleKeyDown)
    window.addEventListener("keyup", this.handleKeyUp)

    this.handleEvent("rambo:pause", () => this.client.pause())
    this.handleEvent("rambo:resume", () => this.client.resume())
    this.handleEvent("rambo:reset", () => this.client.reset())
    this.handleEvent("rambo:shutdown", () => {
      this.fileInput.value = ""
      this.client.shutdown()
    })

    if (this.fileInput.files?.length) {
      // Rehydrate ROM on reconnect without forcing user to reselect.
      const file = this.fileInput.files[0]
      const buffer = await file.arrayBuffer()
      await this.client.loadRom(new Uint8Array(buffer))
      this.pushEvent("rom-loaded", {name: file.name})
    }
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeyDown)
    window.removeEventListener("keyup", this.handleKeyUp)
    if (this.fileInput && this.handleFileChange) {
      this.fileInput.removeEventListener("change", this.handleFileChange)
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
