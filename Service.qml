import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The paper round. One per shell: at the first unlock after the morning
// starts, it sets yesterday's edition, leaves a toast on the step, and keeps
// track of what you've read. Every bar reads this instance.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool active: true

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dataDir: Model.dataPath(home)
  readonly property string stateDir: Model.statePath(home)
  readonly property string builder: decodeURIComponent(String(Qt.resolvedUrl("bin/quattro-daily-build")).replace(/^file:\/\//, ""))
  readonly property string publisher: decodeURIComponent(String(Qt.resolvedUrl("bin/quattro-daily-publish")).replace(/^file:\/\//, ""))
  readonly property var lock: shell && typeof shell.serviceFor === "function" ? shell.serviceFor("omarchy.lock") : null

  function setting(name, fallback) {
    var s = settings || {}
    return s[name] === undefined ? fallback : s[name]
  }

  readonly property int hour: Model.intSetting(setting("hour", 5), 5, 0, 23)
  readonly property bool notify: Model.boolSetting(setting("notify", true), true)
  readonly property bool prose: Model.boolSetting(setting("prose", false), false)
  readonly property bool web: Model.boolSetting(setting("web", false), false)

  // The bound volume, newest first.
  property var editions: []
  readonly property var latest: editions.length ? editions[0] : null
  property string readKey: ""
  readonly property bool unread: Model.unread(editions, readKey)
  readonly property int streak: latest ? Model.streak(editions, latest.date) : 0
  readonly property string streakLine: Model.streakLine(editions.length, streak)

  property bool building: false
  property string buildingKey: ""
  property string lastError: ""
  property bool _announce: false
  // The copy on claude.ai: the same private link, updated each morning.
  property string webUrl: ""
  property string webDate: ""
  property bool publishing: false
  // The last edition the press failed on, so a broken build isn't retried
  // every minute.
  property string failedKey: ""
  property real failedAt: 0

  function isLocked() { return !!(lock && lock.locked) }

  // Sets the edition that's due, if any. `force` rebuilds yesterday's anyway.
  function deliver(force) {
    if (!active || building || isLocked()) return
    var key = force ? Model.shiftDateKey(Model.dateKeyFromDate(new Date()), -1)
      : Model.dueEdition(new Date(), hour, latest ? latest.date : "")
    if (key === "") return
    if (!force && !Model.retryDue(failedKey, failedAt, key, Date.now())) return
    build(key, !force)
  }

  function build(key, announce) {
    if (building || !Model.parseDateKey(key)) return
    building = true
    buildingKey = key
    lastError = ""
    _announce = announce === true && notify
    buildProcess.out = ""
    buildProcess.command = ["node"].concat(Model.buildCommand(builder, key, prose))
    buildProcess.running = true
  }

  function finished(code) {
    if (!building) return
    var key = buildingKey
    building = false
    buildingKey = ""
    indexFile.reload()
    if (code !== 0) {
      failedKey = key
      failedAt = Date.now()
      lastError = "The press jammed. Run quattro-daily-build by hand to see why."
      return
    }
    failedKey = ""
    var r = null
    try { r = JSON.parse(String(buildProcess.out).trim().split("\n").pop()) } catch (e) {}
    if (r && _announce) {
      toastProcess.command = Model.toastCommand("Your paper is here", r.headline + " · " + Model.readingLine(r.minutes))
      toastProcess.running = true
    }
    if (web) publish()
  }

  // Puts the newest edition on claude.ai. The publisher runs a locked-down
  // Claude Code session and takes a few minutes; the link comes back in
  // web/state.json.
  function publish() {
    if (!active || publishing || !latest) return
    publishing = true
    publishProcess.out = ""
    publishProcess.command = ["node", publisher]
    publishProcess.running = true
  }

  function published(code) {
    if (!publishing) return
    publishing = false
    webState.reload()
    var r = null
    try { r = JSON.parse(String(publishProcess.out).trim().split("\n").pop()) } catch (e) {}
    if (code !== 0 || !r || !r.ok) lastError = "The web copy didn't go up" + (r && r.error ? ": " + r.error : ".")
  }

  function openWeb() {
    if (webUrl !== "") Qt.openUrlExternally(webUrl)
  }

  function open(entry) {
    var e = entry || latest
    if (!e) return
    openProcess.command = Model.openCommand(e.path || Model.editionPath(home, e.date))
    openProcess.running = true
    if (e.date >= readKey) markRead(e.date)
  }

  function openIndex() {
    openProcess.command = Model.openCommand(dataDir + "/editions/index.html")
    openProcess.running = true
  }

  function markRead(key) {
    readKey = String(key || (latest ? latest.date : ""))
    readFile.setText(readKey + "\n")
  }

  // Checks on the minute and on every unlock; the first one after the
  // morning starts sets the paper.
  Timer {
    running: root.active
    repeat: true
    interval: 60000
    triggeredOnStart: false
    onTriggered: root.deliver(false)
  }

  Timer {
    id: settle
    interval: 4000
    onTriggered: root.deliver(false)
  }

  Connections {
    target: root.lock
    ignoreUnknownSignals: true
    function onLockedChanged() { if (!root.lock.locked) settle.restart() }
  }

  Process {
    id: buildProcess
    property string out: ""
    stdout: SplitParser { onRead: function(line) { buildProcess.out += line + "\n" } }
    onExited: function(code) { root.finished(code) }
  }

  // A press that never reports back (node missing, a hung fetch) gives up
  // after twenty minutes instead of holding the round forever.
  Timer {
    id: watchdog
    interval: 20 * 60000
    running: root.building
    onTriggered: {
      buildProcess.running = false
      root.finished(-1)
    }
  }

  Process {
    id: publishProcess
    property string out: ""
    stdout: SplitParser { onRead: function(line) { publishProcess.out += line + "\n" } }
    onExited: function(code) { root.published(code) }
  }

  Timer {
    interval: 10 * 60000
    running: root.publishing
    onTriggered: {
      publishProcess.running = false
      root.published(-1)
    }
  }

  FileView {
    id: webState
    path: root.dataDir + "/web/state.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var st = null
      try { st = JSON.parse(text()) } catch (e) {}
      root.webUrl = st ? Model.artifactUrl(st.url) : ""
      root.webDate = st && st.date ? String(st.date) : ""
    }
    onLoadFailed: { root.webUrl = ""; root.webDate = "" }
  }

  Process { id: toastProcess }
  Process { id: openProcess }
  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.stateDir]
    running: true
  }

  FileView {
    id: indexFile
    path: root.dataDir + "/editions.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.editions = Model.parseIndex(text()); settle.restart() }
    onLoadFailed: { root.editions = []; settle.restart() }
    onFileChanged: reload()
  }

  FileView {
    id: readFile
    path: root.stateDir + "/read"
    atomicWrites: true
    printErrors: false
    onLoaded: root.readKey = String(text()).replace(/\s+/g, "")
  }

  // The theme's palette, read from colors.toml and kept current.
  readonly property string colorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
  property var palette: null

  FileView {
    path: root.colorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.palette = Model.parseColors(text())
    onLoadFailed: root.palette = null
    onFileChanged: reload()
  }
}
