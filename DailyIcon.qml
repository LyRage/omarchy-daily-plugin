import QtQuick
import qs.Commons

// A folded broadsheet, drawn: the nameplate rule across the top, a lead
// column and the fold, with a dot in the corner when there's an edition you
// haven't read. Drawn rather than a glyph so it sits on the bar's baseline
// at any size.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color iconColor: "#cccccc"
  property color dotColor: iconColor
  property bool unread: false
  // 0..1: the paper lifts a little while a new edition is being set.
  property real lift: 0

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  onIconColorChanged: canvas.requestPaint()
  onDotColorChanged: canvas.requestPaint()
  onUnreadChanged: canvas.requestPaint()
  onLiftChanged: canvas.requestPaint()
  onIconSizeChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      var s = width
      ctx.reset()
      ctx.clearRect(0, 0, s, s)
      var lw = Math.max(1, s / 13)
      ctx.lineWidth = lw
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.strokeStyle = root.iconColor
      ctx.fillStyle = root.iconColor

      var up = root.lift * s * 0.06
      var x0 = s * 0.12, y0 = s * 0.16 - up, x1 = s * 0.88, y1 = s * 0.86 - up
      // The sheet, with its top-right corner folded down.
      var fold = s * 0.16
      ctx.beginPath()
      ctx.moveTo(x0, y0)
      ctx.lineTo(x1 - fold, y0)
      ctx.lineTo(x1, y0 + fold)
      ctx.lineTo(x1, y1)
      ctx.lineTo(x0, y1)
      ctx.closePath()
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(x1 - fold, y0)
      ctx.lineTo(x1 - fold, y0 + fold)
      ctx.lineTo(x1, y0 + fold)
      ctx.stroke()

      // The nameplate, then a lead column beside two short ones.
      var pad = s * 0.1
      ctx.fillRect(x0 + pad, y0 + s * 0.1, (x1 - fold) - (x0 + pad) - s * 0.04, lw * 1.3)
      var top = y0 + s * 0.27
      var mid = x0 + (x1 - x0) * 0.56
      for (var i = 0; i < 3; i++) {
        var y = top + i * s * 0.135
        ctx.beginPath()
        ctx.moveTo(x0 + pad, y)
        ctx.lineTo(mid - s * 0.04, y)
        ctx.stroke()
        if (i < 2) {
          ctx.beginPath()
          ctx.moveTo(mid + s * 0.04, y)
          ctx.lineTo(x1 - pad, y)
          ctx.stroke()
        }
      }

      if (root.unread) {
        var r = s * 0.15
        ctx.beginPath()
        ctx.arc(x1 - r * 0.2, y1 - r * 0.2, r, 0, Math.PI * 2)
        ctx.fillStyle = root.dotColor
        ctx.fill()
      }
    }
  }
}
