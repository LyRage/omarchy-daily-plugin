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
  // The paper is set in a serif when one is installed, like the edition
  // itself; the bar's font stands in when none is.
  readonly property var installedFonts: Qt.fontFamilies()
  function firstFont(names, fallback) {
    for (var i = 0; i < names.length; i++)
      if (installedFonts.indexOf(names[i]) >= 0) return names[i]
    return fallback
  }
  readonly property string mastheadFamily: firstFont(["Noto Serif Display", "Playfair Display", "Libre Caslon Display", "Noto Serif", "Liberation Serif", "DejaVu Serif"], fontFamily)
  readonly property string serifFamily: firstFont(["Noto Serif", "Source Serif 4", "Libre Caslon Text", "Liberation Serif", "DejaVu Serif"], fontFamily)
  readonly property color rule: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

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

  // The claude.ai copy of the paper, once the Service has published one.
  readonly property string webUrl: service && typeof service.webUrl === "string" ? service.webUrl : ""
  readonly property bool publishing: !!(service && service.publishing === true)

  function openWeb() {
    if (webUrl === "") return
    Qt.openUrlExternally(webUrl)
    close()
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
    contentWidth: panel.fittedContentWidth(Style.space(500))
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
        spacing: 0
        opacity: root.reveal
        transform: Translate { y: (1 - root.reveal) * Style.space(8) }

        // ---- Masthead ---------------------------------------------------
        Rule { weight: 1 }

        Item {
          Layout.fillWidth: true
          implicitHeight: mastTitle.implicitHeight + Style.space(14)

          DailyIcon {
            id: ear
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Style.space(24)
            iconColor: root.foreground
            dotColor: root.accent
            unread: root.service.unread
          }

          Text {
            id: mastTitle
            anchors.centerIn: parent
            width: parent.width - 2 * (ear.width + Style.space(10))
            horizontalAlignment: Text.AlignHCenter
            text: root.current ? root.current.title : Model.APP_NAME
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.mastheadFamily
            font.pixelSize: Style.font.displayLarge
            font.weight: Font.Black
            font.letterSpacing: -0.5
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: ear.width + Style.space(6)
            horizontalAlignment: Text.AlignRight
            visible: !!(root.current && (root.current.weekend || root.current.late))
            text: root.current && root.current.late ? "LATE\nEDITION" : "SUNDAY"
            color: root.current && root.current.late ? root.urgent : root.gold
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - 2
            font.letterSpacing: 1
            lineHeight: 0.9
          }
        }

        DoubleRule {}

        // The folio: date, number and reading time between the rules.
        Item {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          Layout.bottomMargin: Style.space(4)
          implicitHeight: folioDate.implicitHeight
          Folio {
            id: folioDate
            anchors.left: parent.left
            text: root.current ? Model.longDate(root.current.date) : "No editions yet"
          }
          Folio {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.current !== null
            text: root.current ? Model.editionNumber(root.current.date) : ""
          }
          Folio {
            anchors.right: parent.right
            visible: root.current !== null
            text: root.current ? root.current.minutes + " min read" : ""
          }
        }

        Rule { weight: 1 }

        // ---- The lead story ----------------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(14)
          spacing: Style.space(6)
          visible: root.current !== null

          Text {
            Layout.fillWidth: true
            text: root.current ? root.current.kicker : ""
            textFormat: Text.PlainText
            visible: text !== ""
            color: root.gold
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.current ? root.current.headline : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.serifFamily
            font.pixelSize: Style.font.display
            font.weight: Font.Bold
            lineHeight: 1.05
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.current && root.current.deck ? root.current.deck : ""
            textFormat: Text.PlainText
            visible: text !== ""
            color: root.dim
            font.family: root.serifFamily
            font.pixelSize: Style.font.body
            font.italic: true
            lineHeight: 1.15
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(4)
            spacing: Style.space(16)
            PaperLink {
              label: root.cursor === 0 ? "Read the whole paper  →" : "Read this edition  →"
              onActivated: root.read(root.current)
            }
            PaperLink {
              visible: root.webUrl !== "" && root.cursor === 0
              label: "On the web  ↗"
              tint: root.dim
              onActivated: root.openWeb()
            }
            Text {
              visible: root.publishing && root.cursor === 0
              text: "Publishing…"
              color: root.dim
              font.family: root.serifFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.service.streakLine
              visible: text !== "" && root.cursor === 0
              color: root.dim
              font.family: root.serifFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(14)
          visible: root.current === null
          text: root.service.building
            ? "Setting the first edition…"
            : "The first edition arrives at your first unlock after " + Model.pad2(root.service.hour) + ":00, about the day before. Press r to set it now."
          color: root.dim
          font.family: root.serifFamily
          font.pixelSize: Style.font.body
          font.italic: true
          wrapMode: Text.WordWrap
        }

        // ---- The bound volume ----------------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(16)
          spacing: 0
          visible: root.editions.length > 1

          Rule { weight: 2 }
          Text {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(5)
            Layout.bottomMargin: Style.space(3)
            text: "In earlier editions"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6
          }

          ListView {
            id: issuesList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(count, 6) * Style.space(32)
            clip: true
            interactive: count > 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.editions

            delegate: Item {
              id: row
              required property var modelData
              required property int index
              width: issuesList.width
              height: Style.space(32)
              readonly property bool here: index === root.cursor
              readonly property bool hot: here || rowMouse.containsMouse

              Rectangle {
                width: parent.width
                height: 1
                color: root.hairline
              }
              Rectangle {
                width: Style.space(3)
                height: parent.height - Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
                visible: row.here
              }

              Text {
                id: rowDate
                x: Style.space(10)
                width: Style.space(84)
                anchors.verticalCenter: parent.verticalCenter
                text: Model.shortDate(row.modelData.date)
                color: row.hot ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
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
                font.family: root.serifFamily
                font.pixelSize: Style.font.body
                font.weight: row.here ? Font.Bold : Font.Normal
                font.underline: rowMouse.containsMouse
                elide: Text.ElideRight
              }
              Text {
                id: rowMin
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                text: (row.modelData.weekend ? "Sunday · " : "") + row.modelData.minutes + " min"
                color: root.dim
                font.family: root.serifFamily
                font.pixelSize: Style.font.caption
                font.italic: true
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
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(10)
          visible: root.service.building || root.service.lastError !== ""
          text: root.service.building ? "Setting the paper for " + Model.longDate(root.service.buildingKey) + "…" : root.service.lastError
          color: root.service.building ? root.dim : root.urgent
          font.family: root.serifFamily
          font.pixelSize: Style.font.caption
          font.italic: true
          wrapMode: Text.WordWrap
        }

        // ---- Colophon ----------------------------------------------------
        DoubleRule { Layout.topMargin: Style.space(14) }
        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(5)
          horizontalAlignment: Text.AlignHCenter
          text: "↑ ↓ choose   ·   Return read   ·   i every edition   ·   r set it now"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 1.1
          elide: Text.ElideRight
        }
      }
    }
  }

  component Rule: Rectangle {
    property int weight: 1
    Layout.fillWidth: true
    implicitHeight: weight
    color: weight > 1 ? root.foreground : root.rule
  }

  // A newspaper's thick-and-thin rule.
  component DoubleRule: Column {
    Layout.fillWidth: true
    spacing: Style.space(2)
    Rectangle { width: parent.width; height: 2; color: root.foreground }
    Rectangle { width: parent.width; height: 1; color: root.rule }
  }

  component Folio: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.3
    font.features: { "tnum": 1 }
    elide: Text.ElideRight
  }

  component PaperLink: Text {
    id: link
    property string label: ""
    property color tint: root.accent
    signal activated()
    text: label
    color: tint
    font.family: root.serifFamily
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold
    font.underline: linkMouse.containsMouse
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.activated()
    }
  }
}
