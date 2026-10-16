// Gathers what the paper reports, from the machine itself: notification
// history, the daily widgets' own decks and caches, agent logs, git, the
// usage meter and the weather Isobar already fetched. Everything that touches
// the disk or the network lives here; the rest of the builder is pure.

"use strict"

const fs = require("node:fs")
const path = require("node:path")
const crypto = require("node:crypto")
const { execFileSync } = require("node:child_process")
const Model = require("../Model.js")

const HOME = process.env.HOME || ""
const PLUGINS = path.join(HOME, ".config/omarchy/plugins")
const STATE = path.join(HOME, ".local/state/omarchy")
const CACHE = path.join(HOME, ".cache/omarchy")
const UA = "QuattroDaily/1.0 (Omarchy plugin; github.com/atsokolas)"

function run(cmd, args, opts) {
  try {
    return execFileSync(cmd, args, Object.assign({ encoding: "utf8", timeout: 20000, stdio: ["ignore", "pipe", "ignore"], maxBuffer: 64 << 20 }, opts || {}))
  } catch (e) {
    return ""
  }
}

// Exit status only, for checks like `gh auth status`.
function ok(cmd, args) {
  try { execFileSync(cmd, args, { stdio: "ignore", timeout: 15000 }); return true } catch (e) { return false }
}

// Whether a command is on the PATH, without running it.
function has(cmd) {
  for (const dir of String(process.env.PATH || "").split(":")) {
    if (!dir) continue
    try { fs.accessSync(path.join(dir, cmd), fs.constants.X_OK); return true } catch (e) {}
  }
  return false
}

function readText(file) {
  try { return fs.readFileSync(file, "utf8") } catch (e) { return "" }
}

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")) } catch (e) { return null }
}

function list(dir) {
  try { return fs.readdirSync(dir) } catch (e) { return [] }
}

function keyOf(ms) { return Model.dateKeyFromDate(new Date(ms)) }

function inRange(key, from, to) { return key >= from && key <= to }

function curlJson(url) {
  const out = run("curl", ["-fsSLg", "--max-time", "15", "-A", UA, "-H", "AIC-User-Agent: " + UA, url])
  try { return JSON.parse(out) } catch (e) { return null }
}

// A picture as a data URI, resized so the page stays a sensible size.
function imageData(src, width, quality) {
  if (!src) return ""
  const tmp = path.join(require("node:os").tmpdir(), "quattro-daily-" + process.pid + "-" + crypto.randomBytes(4).toString("hex") + ".jpg")
  let input = src
  try {
    if (/^https?:/.test(src)) {
      run("curl", ["-fsSL", "--max-time", "30", "-A", UA, "-o", tmp + ".src", src], { timeout: 45000 })
      if (!fs.existsSync(tmp + ".src")) return ""
      input = tmp + ".src"
    }
    if (!fs.existsSync(input)) return ""
    run("magick", [input + "[0]", "-auto-orient", "-resize", width + "x>", "-strip", "-quality", String(quality || 72), tmp], { timeout: 90000 })
    if (!fs.existsSync(tmp)) return ""
    return "data:image/jpeg;base64," + fs.readFileSync(tmp).toString("base64")
  } finally {
    for (const f of [tmp, tmp + ".src"]) try { fs.unlinkSync(f) } catch (e) {}
  }
}

function md5(file) {
  try { return crypto.createHash("md5").update(fs.readFileSync(file)).digest("hex") } catch (e) { return "" }
}

function installed(name) {
  return fs.existsSync(path.join(PLUGINS, "atsokolas." + name, "manifest.json"))
}

function requirePlugin(name) {
  try { return require(path.join(PLUGINS, "atsokolas." + name, "Model.js")) } catch (e) { return null }
}

// ---- You -------------------------------------------------------------------

function reader() {
  const user = process.env.USER || path.basename(HOME)
  const gecos = run("getent", ["passwd", user]).split(":")[4] || ""
  return { name: Model.firstName(gecos, user) }
}

function desktop() {
  const bg = (() => { try { return fs.realpathSync(path.join(STATE, "current/background")) } catch (e) { return "" } })()
  const themeName = readText(path.join(STATE, "current/theme.name")).trim()
  const pretty = s => String(s || "").replace(/\.[a-z0-9]+$/i, "").replace(/^\d+-/, "").split(/[-_ ]+/).filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
  return {
    theme: pretty(themeName) || "Your theme",
    wallpaper: pretty(path.basename(bg)),
    wallpaperPath: bg,
    palette: Model.parseColors(readText(path.join(STATE, "current/theme/colors.toml")))
  }
}

// ---- Notifications ------------------------------------------------------------

function notifications(app, from, to) {
  const dir = path.join(STATE, "notifications/history")
  const out = []
  for (const f of list(dir)) {
    if (!f.endsWith(".json")) continue
    const n = readJson(path.join(dir, f))
    if (!n || n.app !== app || !n.timestamp) continue
    const k = keyOf(n.timestamp)
    if (inRange(k, from, to)) out.push({ at: n.timestamp, key: k, summary: String(n.summary || ""), body: String(n.body || "") })
  }
  return out.sort((a, b) => a.at - b.at)
}

// ---- The daily widgets ----------------------------------------------------------

function elevation(key, withImage) {
  const E = requirePlugin("elevation")
  if (!E) return null
  const dk = key.replace(/-/g, "")
  const entry = E.entryForDateKey(dk)
  if (!entry) return null
  const pos = E.cyclePosition(dk)
  const cacheDir = path.join(CACHE, "elevation")
  let summary = readJson(E.summaryCachePath(cacheDir, entry.w))
  if (!summary && withImage) summary = curlJson(E.summaryUrl(entry.w))
  const out = {
    name: entry.n, architect: entry.a, year: entry.y, place: entry.p, style: entry.s, form: entry.f,
    note: entry.note || "", position: pos.position, total: pos.total, remaining: pos.remaining,
    extract: summary && summary.extract ? String(summary.extract) : "",
    image: "", imageAlt: entry.n, problem: ""
  }
  if (!withImage) return out
  // Don't trust the cached jpg: it has served the wrong building before.
  // Fetch the original, and say so when the cache holds a twin.
  const remote = summary && (summary.originalimage || summary.thumbnail)
  out.image = remote ? imageData(remote.source, 900, 74) : ""
  const cached = list(cacheDir).filter(f => /\.(jpe?g|png|webp)$/i.test(f))
  const mine = cached.find(f => f.replace(/\.[a-z]+$/i, "") === E.slug(entry.w))
  if (mine) {
    const h = md5(path.join(cacheDir, mine))
    const twin = cached.find(f => f !== mine && md5(path.join(cacheDir, f)) === h)
    if (twin) out.problem = "Elevation's cache holds the same photo for " + entry.n + " and " + twin.replace(/\.[a-z]+$/i, "").replace(/_/g, " ").trim() + "."
  }
  if (!out.image && mine) out.image = imageData(path.join(cacheDir, mine), 900, 74)
  return out
}

function munger(key) {
  const M = requirePlugin("munger")
  if (!M) return null
  const q = M.quoteForDay(Model.dayNumber(key))
  return q ? { text: q.text, tag: q.tag || "", card: (Number(q.index) || 0) + 1 } : null
}

// The cache jpg Easel wrote first on that day is the one it hung.
function easel(key, withMeta, withImage) {
  if (withImage === undefined) withImage = withMeta
  const dir = path.join(CACHE, "easel")
  let best = null
  for (const f of list(dir)) {
    // "<image id>-843.jpg"; themed renders carry a palette key after it.
    if (!/^[0-9a-f-]{36}-\d+\.jpg$/.test(f)) continue
    let st
    try { st = fs.statSync(path.join(dir, f)) } catch (e) { continue }
    if (keyOf(st.mtimeMs) !== key) continue
    if (!best || st.mtimeMs < best.at) best = { file: f, at: st.mtimeMs }
  }
  if (!best) return null
  const imageId = best.file.replace(/-\d+\.jpg$/, "")
  const out = { imageId: imageId, title: "", artist: "", date: "", medium: "", size: "", department: "", accession: "", image: "", page: "" }
  if (withMeta) {
    const fields = "id,title,artist_title,artist_display,date_display,medium_display,dimensions,department_title,main_reference_number,image_id"
    const res = curlJson("https://api.artic.edu/api/v1/artworks/search?query[term][image_id]=" + encodeURIComponent(imageId) + "&fields=" + fields + "&limit=1")
    const a = res && res.data && res.data[0]
    if (a) {
      out.title = a.title || ""
      out.artist = a.artist_title || String(a.artist_display || "").split("\n")[0]
      out.date = a.date_display || ""
      out.medium = a.medium_display || ""
      out.size = String(a.dimensions || "").split(";")[0].split("(")[0].trim()
      out.department = a.department_title || ""
      out.accession = a.main_reference_number || ""
      out.page = a.id ? "https://www.artic.edu/artworks/" + a.id : ""
    }
  }
  if (withImage) out.image = imageData(path.join(dir, best.file), 640, 76)
  return out
}

// Easel announces each day's piece; the toast on the delivery day names it.
function easelToday(key) {
  const n = notifications("Easel", key, key).find(x => /today/i.test(x.summary))
  if (!n) return null
  const parts = n.body.split(/\s+—\s+/)
  return { title: parts[0] || n.body, credit: parts.slice(1).join(" — ") }
}

// ---- Agents --------------------------------------------------------------------------

const SKIP_PREFIX = /^\s*(<|\[Request interrupted|Caveat:)/

function textOf(content) {
  if (typeof content === "string") return content
  if (Array.isArray(content)) return content.filter(c => c && c.type === "text").map(c => c.text).join("\n")
  return ""
}

// Typed prompts, sessions and what they shipped, per local day.
function claudeSessions(from, to) {
  const root = path.join(HOME, ".claude/projects")
  const own = path.join(HOME, ".local/share/quattro-daily")
  const sessions = []
  for (const proj of list(root)) {
    const dir = path.join(root, proj)
    for (const f of list(dir)) {
      if (!f.endsWith(".jsonl")) continue
      const file = path.join(dir, f)
      let st
      try { st = fs.statSync(file) } catch (e) { continue }
      if (keyOf(st.mtimeMs) < from) continue
      const s = { id: f.replace(/\.jsonl$/, ""), cwd: "", prompts: [], commits: 0, files: new Set(), published: 0, installs: 0, outputTokens: 0, model: "", days: {} }
      for (const line of readText(file).split("\n")) {
        if (!line) continue
        let e
        try { e = JSON.parse(line) } catch (err) { continue }
        const t = Date.parse(e.timestamp || "")
        if (!t) continue
        const k = keyOf(t)
        if (!inRange(k, from, to)) continue
        if (e.cwd && !s.cwd) s.cwd = e.cwd
        if (e.type === "user" && !e.isMeta && e.message && typeof e.message.content === "string") {
          const text = e.message.content.trim()
          if (text && !SKIP_PREFIX.test(text)) { s.prompts.push({ at: t, key: k, text: text }); s.days[k] = (s.days[k] || 0) + 1 }
        }
        if (e.type === "assistant" && e.message) {
          const u = e.message.usage
          if (u) s.outputTokens += Number(u.output_tokens) || 0
          if (e.message.model && !/synthetic/.test(e.message.model)) s.model = e.message.model
          for (const c of Array.isArray(e.message.content) ? e.message.content : []) {
            if (!c || c.type !== "tool_use") continue
            const inp = c.input || {}
            if ((c.name === "Edit" || c.name === "Write") && inp.file_path) s.files.add(inp.file_path)
            if (c.name === "Artifact" && (!inp.action || inp.action === "publish")) s.published++
            if (c.name === "Bash" && typeof inp.command === "string") {
              s.commits += (inp.command.match(/\bgit (-C \S+ )?commit\b/g) || []).length
              if (/\b(pacman -S|yay -S|omarchy plugin add|systemctl --user enable)\b/.test(inp.command)) s.installs++
            }
          }
        }
      }
      if (s.cwd && s.cwd.indexOf(own) === 0) continue
      if (!s.prompts.length) continue
      s.files = Array.from(s.files)
      s.firstAt = s.prompts[0].at
      s.lastAt = s.prompts[s.prompts.length - 1].at
      s.agent = "Claude Code"
      sessions.push(s)
    }
  }
  return sessions.sort((a, b) => a.firstAt - b.firstAt)
}

function codexSessions(from, to) {
  const out = []
  let k = from
  while (k && k <= to) {
    const dir = path.join(HOME, ".codex/sessions", k.slice(0, 4), k.slice(5, 7), k.slice(8, 10))
    for (const f of list(dir)) {
      if (!f.endsWith(".jsonl")) continue
      const prompts = []
      let cwd = ""
      for (const line of readText(path.join(dir, f)).split("\n")) {
        let e
        try { e = JSON.parse(line) } catch (err) { continue }
        const p = e.payload || e
        if (p && p.cwd && !cwd) cwd = p.cwd
        if (p && p.type === "message" && p.role === "user") {
          const text = textOf(p.content).trim()
          const t = Date.parse(e.timestamp || "") || 0
          if (text && !SKIP_PREFIX.test(text)) prompts.push({ at: t, key: k, text: text })
        }
      }
      if (prompts.length) out.push({ id: f, cwd: cwd, prompts: prompts, commits: 0, files: [], published: 0, installs: 0, outputTokens: 0, model: "", days: { [k]: prompts.length }, firstAt: prompts[0].at, lastAt: prompts[prompts.length - 1].at, agent: "Codex" })
    }
    k = Model.shiftDateKey(k, 1)
  }
  return out
}

function usage() {
  const dir = path.join(STATE, "agents/usage")
  const out = []
  for (const f of list(dir)) {
    const u = readJson(path.join(dir, f))
    if (!u || !u.name) continue
    out.push({
      name: u.name,
      limits: Array.isArray(u.limits) ? u.limits.filter(l => l && isFinite(Number(l.percent))) : [],
      needsAuth: /auth login/.test(String(u.authHelpText || "")) && !!u.authHelpText,
      authHelp: String(u.authHelpText || ""),
      updatedAt: Date.parse(u.updatedAt || "") || 0
    })
  }
  return out
}

// ---- The plugin desk ------------------------------------------------------------------

// Every installed plugin, whoever wrote it. Only commits under your own git
// identity count, so updates pulled from someone else's repository never
// pass for your work.
function pluginDesk(from, to) {
  const out = []
  for (const d of list(PLUGINS).sort()) {
    const dir = path.join(PLUGINS, d)
    const manifest = readJson(path.join(dir, "manifest.json"))
    if (!manifest || typeof manifest !== "object") continue
    const name = String(manifest.name || d.replace(/^[^.]+\./, ""))
    const tracked = fs.existsSync(path.join(dir, ".git"))
    const p = { id: d, name: name, tracked: tracked, commits: [], dirty: false }
    if (tracked) {
      const email = run("git", ["-C", dir, "config", "user.email"]).trim()
      const since = Model.parseDateKey(from), until = Model.parseDateKey(Model.shiftDateKey(to, 1))
      const log = email ? run("git", ["-C", dir, "log", "-F", "--author=<" + email + ">", "--since=" + since.toISOString(), "--until=" + until.toISOString(), "--format=%at%x09%s"]) : ""
      for (const line of log.split("\n")) {
        const m = /^(\d+)\t(.*)$/.exec(line)
        if (m) p.commits.push({ at: Number(m[1]) * 1000, key: keyOf(Number(m[1]) * 1000), subject: m[2] })
      }
      p.dirty = run("git", ["-C", dir, "status", "--porcelain"]).trim() !== ""
    }
    out.push(p)
  }
  return out
}

function carrel() {
  const board = readJson(path.join(STATE, "carrel/board.json"))
  const items = board && Array.isArray(board.items) ? board.items : []
  const by = {}
  for (const it of items) by[it.list] = (by[it.list] || []).concat(it.title)
  return { total: items.length, lists: by }
}

// ---- Weather -------------------------------------------------------------------------------

function shellEntry(id) {
  const shell = readJson(path.join(HOME, ".config/omarchy/shell.json"))
  let found = null
  const walk = o => {
    if (found || !o || typeof o !== "object") return
    if (o.id === id && !Array.isArray(o)) { found = o; return }
    for (const v of Object.values(o)) walk(v)
  }
  walk(shell)
  return found
}

function placeKey(lat, lon) { return Number(lat).toFixed(3) + "," + Number(lon).toFixed(3) }

function forecastUrl(lat, lon, from, to) {
  return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon +
    "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,precipitation_sum,uv_index_max" +
    "&hourly=temperature_2m,wind_speed_10m&current=temperature_2m,weather_code,is_day&timezone=auto&start_date=" + from + "&end_date=" + to
}

// Without Isobar's cache (or with it too short), the forecast comes from
// Open-Meteo for Isobar's place, or, with no place on file, wherever wttr.in
// places your IP address. `net` false keeps it all local.
function weather(key, net) {
  if (net === undefined) net = true
  const cache = readJson(path.join(CACHE, "isobar/forecast.json"))
  let raw = cache && cache.raw ? cache.raw : null
  let place = cache && cache.place ? cache.place : ""
  let source = raw ? "Isobar" : ""
  // Isobar keeps a day of history; when that doesn't reach back far enough,
  // ask Open-Meteo for the same place directly.
  if (net && (!raw || !Model.weatherDay(raw, key))) {
    let lat = NaN, lon = NaN
    if (cache && cache.key) [lat, lon] = String(cache.key).split(",").map(Number)
    if (!isFinite(lat)) {
      const w = curlJson("https://wttr.in/?format=j1")
      const a = w && w.nearest_area && w.nearest_area[0]
      if (a) { lat = Number(a.latitude); lon = Number(a.longitude); place = place || (a.areaName && a.areaName[0] && a.areaName[0].value) || "" }
    }
    if (isFinite(lat)) {
      const f = curlJson(forecastUrl(lat, lon, key, Model.shiftDateKey(key, 3)))
      if (f && f.daily) { raw = f; source = "Open-Meteo" }
    }
  }
  const lang = process.env.LC_ALL || process.env.LC_MEASUREMENT || process.env.LANG || ""
  const entry = shellEntry("atsokolas.isobar") || {}
  const unit = String(entry.unit || "auto")
  const imperial = unit === "imperial" || (unit === "auto" && /_(US|LR|MM)\b/.test(lang))
  // The places you keep in Isobar, as Isobar last saw them.
  const placesCache = readJson(path.join(CACHE, "isobar/places.json")) || {}
  const places = []
  for (const p of Array.isArray(entry.places) ? entry.places : []) {
    if (!p || !p.name || !isFinite(Number(p.latitude))) continue
    const e = placesCache.entries && placesCache.entries[placeKey(p.latitude, p.longitude)]
    let f = null
    try { f = e ? JSON.parse(e.raw) : null } catch (err) {}
    places.push({ name: p.name, onBar: p.onBar === true, current: f && f.current ? f.current : null, fetchedAt: e ? e.fetchedAt : 0 })
  }
  return { raw: raw, place: place, source: source, imperial: imperial, places: places }
}

// ---- The back page --------------------------------------------------------------------------

function almanac() {
  const first = /^\[(\d{4}-\d{2}-\d{2})/.exec(readText(path.join(STATE, "first-run.log")))
  const df = run("df", ["-B1", "--output=avail,size", HOME]).trim().split("\n").pop().trim().split(/\s+/).map(Number)
  const binds = run("omarchy", ["menu", "keybindings", "--print"])
  return {
    since: first ? first[1] : "",
    diskFree: df.length === 2 && isFinite(df[0]) ? df[0] : NaN,
    diskSize: df.length === 2 && isFinite(df[1]) ? df[1] : NaN,
    bindings: Model.parseKeybindings(binds)
  }
}

function looseEnds(desk, usageList) {
  const out = []
  for (const u of usageList) if (u.needsAuth) out.push({ kind: "WANTED", text: "A fresh sign-in for " + u.name + ". The usage meter is running on old numbers.", code: (/`([^`]+)`/.exec(u.authHelp) || [])[1] || "" })
  if (has("gh") && !ok("gh", ["auth", "status"])) out.push({ kind: "WANTED", text: "A GitHub CLI login, for anything that checks provenance or ships a release.", code: "gh auth login" })
  for (const p of desk) if (!p.tracked) out.push({ kind: "SEEKING", text: "A git repository for " + p.name + ", a plugin without one.", code: "" })
  for (const p of desk) if (p.tracked && p.dirty) out.push({ kind: "NOTICE", text: p.name + " has changes that aren't committed yet.", code: "" })
  return out
}

module.exports = {
  run, readJson, readText, imageData, reader, desktop, notifications, elevation, munger, easel, easelToday,
  claudeSessions, codexSessions, usage, pluginDesk, carrel, weather, almanac, looseEnds, shellEntry, has, installed
}
