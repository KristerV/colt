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
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/colt"
import topbar from "../vendor/topbar"

const FeedbackModal = {
  mounted() {
    this.observer = new MutationObserver(() => {
      if (!this.el.classList.contains("hidden")) {
        const u = this.el.querySelector("#feedback-url")
        if (u) u.value = window.location.pathname + window.location.search
      }
    })
    this.observer.observe(this.el, {attributes: true, attributeFilter: ["class"]})

    this.handleEvent("feedback:sent", () => {
      this.el.classList.add("hidden")
      const ta = this.el.querySelector("#feedback-body")
      if (ta) ta.value = ""
    })
  },
  destroyed() {
    if (this.observer) this.observer.disconnect()
  }
}

// Trix rich-text editor bridge. The hidden input mirrors Trix's HTML
// output; we push a phx-blur "trix_input" event so LiveView keeps state
// without forms or live-form noise.
const TrixEditor = {
  mounted() {
    const editor = this.el.querySelector("trix-editor")
    const input  = this.el.querySelector("input[type=hidden]")
    if (!editor || !input) return
    this.onBlur = () => {
      this.pushEventTo(this.el, "trix_input", { value: input.value })
    }
    editor.addEventListener("blur", this.onBlur)
  },
  destroyed() {
    const editor = this.el.querySelector("trix-editor")
    if (editor && this.onBlur) editor.removeEventListener("blur", this.onBlur)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, FeedbackModal, TrixEditor},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Auto-close the mobile nav drawer after any live navigation so it doesn't
// linger over freshly-patched content. No-op on desktop (drawer is static).
window.addEventListener("phx:page-loading-stop", _info => {
  const sidebar = document.getElementById("liid-sidebar")
  const backdrop = document.getElementById("liid-nav-backdrop")
  if (sidebar) sidebar.classList.add("-translate-x-full")
  if (backdrop) backdrop.classList.add("hidden")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

