// Demo-deck hooks: playback on /demo, recording in /admin/deck.
//
// Both sides deliberately keep one long-lived <video> element. On the player
// that is what preserves the autoplay permission granted by the Play click —
// swapping src on an existing element stays "user-initiated", creating a new
// element does not.

// ---------------------------------------------------------------- player

export const DeckPlayer = {
  mounted() {
    this.src = null
    this.timer = null

    // Always report the end of a clip. Whether that advances the deck is the
    // server's call — pausing stops the deck moving on, it doesn't stop the
    // narration on the slide you're looking at.
    this.el.addEventListener("ended", () => this.pushEvent("advance"))

    // A clip that 404s or fails to decode never fires `ended`, and the dwell
    // timer is only armed for slides with no clip at all — so without this the
    // deck sits on that slide forever with only the manual arrows to escape.
    this.el.addEventListener("error", () => this.startFallback())

    // The video has to be started inside the Play click's own handler,
    // otherwise the browser refuses audio for the rest of the deck. Matched on
    // the attribute rather than an id because the button lives in the cover
    // *slide*, and each variant styles its own — see Slides.
    document.addEventListener("click", this.onDocClick = (e) => {
      if (e.target.closest("[data-deck-start]")) this.unlock()
    })

    document.addEventListener("keydown", this.onKey = (e) => {
      if (e.target.matches("input, textarea")) return
      if (e.code === "Space") { e.preventDefault(); this.pushEvent("toggle_pause") }
      if (e.code === "ArrowRight") this.pushEvent("next")
      if (e.code === "ArrowLeft") this.pushEvent("prev")
    })

    this.sync()
  },

  updated() { this.sync() },

  destroyed() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
    this.clearTimer()
  },

  sync() {
    const src = this.el.dataset.src || null
    const index = this.el.dataset.index
    const started = this.el.dataset.started === "true"

    // Keyed on the slide index, not on src: two un-narrated slides in a row
    // both have a null src, and without this a manual "next" would leave the
    // previous slide's dwell timer running and cut the new one short.
    if (index !== this.index) {
      this.index = index
      this.src = src
      this.clearTimer()
      if (src) { this.el.src = src; this.el.currentTime = 0 } else { this.el.removeAttribute("src") }
      this.preloadNext()
    }

    if (started) { this.play() } else { this.pause() }
  },

  // The cover slide carries the Play button but no narration of its own, so
  // there is nothing to start inside the click — and a play() that never
  // happens during a gesture means every later clip is muted or blocked.
  // Load the *next* slide's clip onto the element and play it silently for an
  // instant: that is what marks this element as user-started. The index guard
  // is for the case where the server's advance beats the play promise, which
  // would otherwise pause the deck the moment it began.
  unlock() {
    // Any clip will do — this plays one silently just to mark the element as
    // user-started. Falling back past the next slide matters: with nothing
    // recorded on slide 2, keying off data-next-src alone means the unlock
    // never runs and the first clip that *does* exist is blocked or muted.
    const src = this.el.dataset.nextSrc || this.el.dataset.anySrc
    if (!src || this.el.getAttribute("src")) return

    const at = this.el.dataset.index
    this.el.src = src
    this.el.volume = 0

    const p = this.el.play()
    if (p && p.then) {
      p.then(() => {
        if (this.el.dataset.index === at) this.el.pause()
        this.el.volume = 1
      }).catch(() => { this.el.volume = 1 })
    } else {
      this.el.volume = 1
    }
  },

  play() {
    if (this.src) {
      const p = this.el.play()
      if (p && p.catch) p.catch(() => {})
    } else {
      // No recording for this slide yet — hold it for the fallback dwell so
      // the deck still runs end to end before anything has been recorded.
      this.startFallback()
    }
  },

  pause() {
    if (this.src) this.el.pause()
    this.clearTimer()
  },

  startFallback() {
    if (this.timer) return
    const total = parseInt(this.el.dataset.fallbackMs || "11000", 10)
    this.timer = setTimeout(() => { this.timer = null; this.pushEvent("advance") }, total)
  },

  clearTimer() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
  },

  // Warm only the next clip. Fetching the whole deck up front is 80MB of
  // video for a prospect who may bounce on slide two.
  preloadNext() {
    const next = this.el.dataset.nextSrc
    if (!next || next === this.preloaded) return
    this.preloaded = next
    const v = document.createElement("video")
    v.preload = "auto"
    v.src = next
  },
}

// getUserMedia's DOMExceptions are unhelpful on their own ("NotAllowedError").
// Say what to actually do about each one.
function describeMediaError(err) {
  switch (err && err.name) {
    case "NotAllowedError":
      return "Camera/mic access was blocked. Allow it in the address-bar icon, then reload."
    case "NotFoundError":
    case "OverconstrainedError":
      return "No camera or microphone found on this machine."
    case "NotReadableError":
      return "The camera is busy — close Zoom/Meet/OBS and reload."
    default:
      return String(err)
  }
}

// ---------------------------------------------------------------- recorder

export const DeckRecorder = {
  mounted() {
    this.chunks = []
    this.recorder = null
    this.stream = null
    // The preview lives inside the deck stage, not inside this hook's element,
    // so that it is literally the same bubble the player renders.
    this.preview = document.getElementById("studio-preview")
    this.startedAt = null

    document.addEventListener("click", this.onDocClick = (e) => {
      if (e.target.closest("#studio-record")) this.toggle()
    })

    document.addEventListener("keydown", this.onKey = (e) => {
      if (e.target.matches("input, textarea, select")) return
      if (e.code === "Space") { e.preventDefault(); this.toggle() }
      // Never skip slides mid-take — that would silently discard the recording.
      if (e.code === "KeyN" && !(this.recorder && this.recorder.state === "recording")) {
        this.pushEvent("next_slide")
      }
    })

    this.handleEvent("deck:arm", () => this.arm())
    this.arm()
  },

  destroyed() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
    clearInterval(this.ticker)
    if (this.stream) this.stream.getTracks().forEach(t => t.stop())
  },

  async arm() {
    if (this.stream) return

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.pushEvent("camera_error", {message: "This browser won't share a camera over plain http — use localhost or https."})
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        // 540p is what gets stored anyway (the bubble renders at ~150px), and
        // recording at 720p only makes a file that has to crawl up the socket.
        video: {width: {ideal: 960}, height: {ideal: 540}, facingMode: "user"},
        audio: {echoCancellation: true, noiseSuppression: true},
      })
    } catch (err) {
      this.pushEvent("camera_error", {message: describeMediaError(err)})
      return
    }

    this.preview.srcObject = this.stream
    this.preview.muted = true
    // A rejected play() must not read as a broken camera: the stream is fine,
    // it's only the on-screen preview that didn't start.
    try { await this.preview.play() } catch (_e) {}

    const video = this.stream.getVideoTracks()[0]
    const audio = this.stream.getAudioTracks()[0]

    // Report the device names back. Which camera and mic you are actually
    // recording through is the one thing worth showing on screen — a stream
    // that isn't the device you expect looks identical to one that is.
    this.pushEvent("camera_ready", {
      video_label: video ? video.label : null,
      audio_label: audio ? audio.label : null,
    })
  },

  // Prefer mp4 where the browser can produce it: Safari plays webm
  // inconsistently, and a prospect opening the deck on an iPhone is exactly
  // the case we cannot afford to get wrong. No server-side transcode.
  mimeType() {
    const candidates = [
      'video/mp4;codecs="avc1.42E01E,mp4a.40.2"',
      "video/mp4",
      'video/webm;codecs="vp9,opus"',
      "video/webm",
    ]
    return candidates.find(t => MediaRecorder.isTypeSupported(t)) || ""
  },

  toggle() {
    if (this.recorder && this.recorder.state === "recording") this.stop()
    else this.start()
  },

  start() {
    // Silently doing nothing here is how you end up unsure whether a take
    // happened at all. Say so, then try to arm.
    if (!this.stream) {
      this.pushEvent("camera_error", {message: "Camera isn't ready — nothing was recorded. Allow access and try again."})
      this.arm()
      return
    }

    this.chunks = []
    const mimeType = this.mimeType()
    // A talking head against a static background needs nowhere near the
    // browser's default ~2.5Mbps. This is the difference between a 30-second
    // take being a 9MB upload and a 2MB one.
    this.recorder = new MediaRecorder(this.stream, {
      ...(mimeType ? {mimeType} : {}),
      videoBitsPerSecond: 600_000,
      audioBitsPerSecond: 64_000,
    })
    this.recorder.ondataavailable = e => { if (e.data.size) this.chunks.push(e.data) }
    this.recorder.onstop = () => this.finish(mimeType)
    this.startedAt = performance.now()
    this.recorder.start()
    this.tick()
    this.pushEvent("recording_started", {})
  },

  stop() {
    if (this.recorder && this.recorder.state === "recording") this.recorder.stop()
    clearInterval(this.ticker)
    this.ticker = null
  },

  // A counter that visibly runs while the take is in progress. The element is
  // looked up on every paint, not captured once: recording starts before the
  // server has re-rendered, so at this point #studio-timer does not exist yet.
  tick() {
    const paint = () => {
      const el = document.getElementById("studio-timer")
      if (!el) return
      const s = (performance.now() - this.startedAt) / 1000
      el.textContent = `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
    }
    paint()
    this.ticker = setInterval(paint, 200)
  },

  async finish(mimeType) {
    const durationMs = Math.round(performance.now() - this.startedAt)
    const type = mimeType || "video/webm"
    const blob = new Blob(this.chunks, {type})

    // Upload only once the server has acknowledged the duration. Dispatching
    // into the file input while that round-trip's DOM patch is still landing
    // loses the tracked file and the upload sits at 0% forever.
    this.pushEvent("recording_stopped", {duration_ms: durationMs}, () => {
      const ext = type.includes("mp4") ? "mp4" : "webm"
      this.upload("clip", [new File([blob], `clip.${ext}`, {type})])
    })
  },
}
