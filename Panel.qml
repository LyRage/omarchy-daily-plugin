import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "atsokolas.daily"
  ipcTarget: "atsokolas.daily"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool openedFromHotkey: false
  // The edition under the cursor: 0 is the newest.
  property int cursor: 0

  readonly property var barIdentity: hostWidget || root
  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  // Every colour from the theme palette: the shell's Color singleton isn't
  // visible to third-party plugins.
  readonly property var palette: service ? service.palette : null
  readonly property color foreground: bar ? bar.foreground : (palette ? palette.foreground : "#cccccc")
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: palette ? palette.accent : foreground
  readonly property color gold: palette ? palette.yellow : accent
  readonly property color urgent: palette ? palette.red : foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var editions: service ? service.editions : []
  readonly property var current: editions.length ? editions[Math.max(0, Math.min(cursor, editions.length - 1))] : null

  property real reveal: 1
  NumberAnimation { id: revealAnim; target: root; property: "reveal"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
  onOpenedChanged: if (opened) { cursor = 0; revealAnim.restart() }

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function move(delta) {
    if (!editions.length) return
    cursor = Math.max(0, Math.min(editions.length - 1, cursor + delta))
    issuesList.positionViewAtIndex(Math.max(0, cursor - 1), ListView.Contain)
  }

  function read(entry) {
    if (!entry) return
    service.open(entry)
    close()
  }

  Service {
    id: localService
    active: root.sharedService === null
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(page.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.move(dy !== 0 ? dy : dx) }
      onActivateRequested: root.read(root.current)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text || "")
        if (key === "i") { root.service.openIndex(); root.close() }
        else if (key === "r") root.service.deliver(true)
        else if (key === "g") root.move(-root.cursor)
      }

      ColumnLayout {
        id: page
        width: parent.width
        spacing: Style.space(12)
        opacity: root.reveal
        transform: Translate { y: (1 - root.reveal) * Style.space(8) }

        // ---- Masthead ---------------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          DailyIcon {
            iconSize: Style.space(30)
            iconColor: root.foreground
            dotColor: root.accent
            unread: root.service.unread
            Layout.alignment: Qt.AlignTop
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              Layout.fillWidth: true
              text: root.current ? root.current.title : Model.APP_NAME
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              text: root.current
                ? Model.longDate(root.current.date) + "  ·  " + Model.editionNumber(root.current.date)
                : "No editions yet"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: root.foreground; opacity: 0.25 }

        // ---- The edition under the cursor --------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          visible: root.current !== null

          Text {
            Layout.fillWidth: true
            text: root.current ? root.current.kicker.toUpperCase() : ""
            textFormat: Text.PlainText
            visible: text !== ""
            color: root.gold
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.4
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.current ? root.current.headline : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
              text: root.current ? Model.readingLine(root.current.minutes) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Tag { visible: !!(root.current && root.current.weekend); label: "Sunday"; tint: root.gold }
            Tag { visible: !!(root.current && root.current.late); label: "Late edition"; tint: root.urgent }
            Item { Layout.fillWidth: true }
            Text {
              text: root.service.streakLine
              visible: text !== "" && root.cursor === 0
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.current === null
          text: root.service.building
            ? "Setting the first edition…"
            : "The first edition arrives at your first unlock after " + Model.pad2(root.service.hour) + ":00, about the day before. Press r to set it now."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---- Back issues -------------------------------------------------
        Text {
          Layout.fillWidth: true
          visible: root.editions.length > 1
          text: "BACK ISSUES"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.4
        }

        ListView {
          id: issuesList
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(count, 6) * Style.space(30)
          visible: root.editions.length > 1
          clip: true
          interactive: count > 6
          boundsBehavior: Flickable.StopAtBounds
          model: root.editions

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: issuesList.width
            height: Style.space(30)
            readonly property bool hot: index === root.cursor || rowMouse.containsMouse

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: row.hot ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : "transparent"
            }
            Rectangle {
              width: Style.space(2)
              height: parent.height - Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              color: root.accent
              visible: row.index === root.cursor
            }

            Text {
              id: rowDate
              x: Style.space(10)
              width: Style.space(86)
              anchors.verticalCenter: parent.verticalCenter
              text: Model.shortDate(row.modelData.date)
              color: row.hot ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.features: { "tnum": 1 }
            }
            Text {
              anchors.left: rowDate.right
              anchors.right: rowMin.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.headline
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              id: rowMin
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.minutes + " min"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.cursor = row.index
              onClicked: root.read(row.modelData)
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.service.building || root.service.lastError !== ""
          text: root.service.building ? "Setting the paper for " + Model.longDate(root.service.buildingKey) + "…" : root.service.lastError
          color: root.service.building ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          text: "↑ ↓ choose   ·   Return read   ·   i all editions   ·   r set it now"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component Tag: Rectangle {
    property string label: ""
    property color tint: root.accent
    implicitWidth: tagText.implicitWidth + Style.space(10)
    implicitHeight: tagText.implicitHeight + Style.space(4)
    radius: Style.space(3)
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.6)
    Text {
      id: tagText
      anchors.centerIn: parent
      text: parent.label.toUpperCase()
      color: parent.tint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption - 1
      font.letterSpacing: 1
    }
  }
}
