import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "lyrage.daily"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // From the theme palette: the shell's Color singleton isn't visible to plugins.
  readonly property color accent: service && service.palette ? service.palette.accent : (bar ? bar.barForeground : "#cccccc")

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  IpcHandler {
    target: "lyrage.daily"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    // Opens the newest edition in the browser.
    function read(): void { if (root.service) root.service.open(null) }
    // Sets yesterday's edition now, whether or not it's due.
    function build(): string { if (!root.service) return "no service"; root.service.deliver(true); return "setting" }
    // Puts the newest edition on claude.ai now.
    function publish(): string { if (!root.service) return "no service"; root.service.publish(); return "publishing" }
    function web(): string { return root.service ? root.service.webUrl : "" }
    function latest(): string { return root.service && root.service.latest ? root.service.latest.path : "" }
    function status(): string {
      var s = root.service
      if (!s) return "{}"
      return JSON.stringify({ latest: s.latest ? s.latest.date : "", unread: s.unread, building: s.building, editions: s.editions.length, error: s.lastError, web: s.webUrl, publishing: s.publishing })
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.max(Style.bar.iconSlot, icon.width + button.scaledHorizontalMargin * 2)
    foreground: root.opened ? root.accent : (root.bar ? root.bar.barForeground : "#cccccc")
    tooltipText: root.service && root.service.building ? "Setting the paper…" : Model.tooltipText(root.service ? root.service.latest : null)
    horizontalMargin: 8.75
    verticalPadding: 6

    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.open(null) }
      else if (b === Qt.RightButton) { if (root.service) root.service.openIndex() }
      else root.togglePanel()
    }

    DailyIcon {
      id: icon
      anchors.centerIn: parent
      iconSize: Math.round(button.fontSize * 1.18)
      iconColor: button.foreground
      dotColor: root.accent
      unread: !!(root.service && root.service.unread)
      // While the press runs, the paper breathes.
      SequentialAnimation on lift {
        running: !!(root.service && root.service.building)
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) icon.lift = 0
      }
    }
  }
}
