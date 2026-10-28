import QtQuick

// A thin circular progress arc: the countdown language of the widget.
//
// Drawn on a Canvas rather than a Shape so the stroke can carry round caps and
// an optional fading track at a couple of pixels wide, where Shape's arc maths
// stops paying for itself. It repaints only when a property it actually draws
// changes, so a 20 px bar ring costs nothing between ticks.
Item {
  id: root

  property real progress: 1.0        // 0..1 remaining
  property real thickness: 2
  property color color: "#ffffff"
  property color trackColor: "transparent"
  property real startAngle: -90      // -90 = 12 o'clock

  implicitWidth: 22
  implicitHeight: 22

  onProgressChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()
  onThicknessChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    renderTarget: Canvas.Image

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var size = Math.min(width, height)
      var radius = size / 2 - root.thickness / 2
      var cx = width / 2
      var cy = height / 2
      var from = root.startAngle * Math.PI / 180
      var span = Math.max(0, Math.min(1, root.progress)) * Math.PI * 2

      ctx.lineWidth = root.thickness
      ctx.lineCap = "round"

      if (root.trackColor.a > 0) {
        ctx.beginPath()
        ctx.arc(cx, cy, radius, 0, Math.PI * 2)
        ctx.strokeStyle = root.trackColor
        ctx.stroke()
      }

      if (span > 0.0005) {
        ctx.beginPath()
        ctx.arc(cx, cy, radius, from, from + span)
        ctx.strokeStyle = root.color
        ctx.stroke()
      }
    }
  }
}
