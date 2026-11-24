import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShellQt
import com.mirql.ring 1.0

Window {
    id: root
    width: 420
    height: 420
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: bridge.visible

    LayerShellQt.Window.layer: LayerShellQt.Window.LayerOverlay
    // AnchorNone centres the surface on its output (the compositor-chosen
    // one below) -- not on the cursor; see main.rs's module doc for why.
    LayerShellQt.Window.anchors: LayerShellQt.Window.AnchorNone
    LayerShellQt.Window.exclusionZone: 0
    LayerShellQt.Window.screenConfiguration: LayerShellQt.Window.ScreenFromCompositor
    LayerShellQt.Window.keyboardInteractivity: bridge.visible
        ? LayerShellQt.Window.KeyboardInteractivityExclusive
        : LayerShellQt.Window.KeyboardInteractivityNone

    RingBridge { id: bridge }

    property bool ackedThisShow: false
    property real mouseX: width / 2
    property real mouseY: height / 2

    onVisibleChanged: if (visible) ackedThisShow = false
    onFrameSwapped: {
        if (visible && !ackedThisShow) {
            ackedThisShow = true
            bridge.ackShown()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: bridge.visible = false

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: (mouse) => {
                root.mouseX = mouse.x
                root.mouseY = mouse.y
                ring.requestPaint()
            }
            onClicked: bridge.visible = false
        }

        Canvas {
            id: ring
            anchors.fill: parent
            renderStrategy: Canvas.Immediate
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2, cy = height / 2
                var radius = 140, square = 72
                var labels = ["Term", "Files", "Web", "Mail", "Notes", "Lock"]
                var pointerAngle = Math.atan2(root.mouseY - cy, root.mouseX - cx)

                function slotAngle(i) { return -Math.PI / 2 + i * (Math.PI * 2 / 6) }
                function angularDistance(a, b) {
                    var twoPi = Math.PI * 2
                    var d = Math.abs(a - b) % twoPi
                    return d > Math.PI ? twoPi - d : d
                }

                var nearest = 0, best = Infinity
                for (var i = 0; i < 6; i++) {
                    var d = angularDistance(slotAngle(i), pointerAngle)
                    if (d < best) { best = d; nearest = i }
                }

                function roundedRect(x, y, w, h, r) {
                    ctx.beginPath()
                    ctx.moveTo(x + r, y)
                    ctx.arcTo(x + w, y, x + w, y + h, r)
                    ctx.arcTo(x + w, y + h, x, y + h, r)
                    ctx.arcTo(x, y + h, x, y, r)
                    ctx.arcTo(x, y, x + w, y, r)
                    ctx.closePath()
                }

                for (i = 0; i < 6; i++) {
                    var a = slotAngle(i)
                    var px = cx + radius * Math.cos(a)
                    var py = cy + radius * Math.sin(a)
                    var highlighted = (i === nearest)
                    if (highlighted) {
                        roundedRect(px - square / 2 - 12, py - square / 2 - 12, square + 24, square + 24, 14)
                        ctx.fillStyle = "rgba(120, 170, 255, 0.27)"
                        ctx.fill()
                    }
                    roundedRect(px - square / 2, py - square / 2, square, square, 10)
                    ctx.fillStyle = highlighted ? "rgb(90, 140, 230)" : "rgba(40, 44, 56, 0.92)"
                    ctx.fill()
                    ctx.lineWidth = 1.5
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.24)"
                    ctx.stroke()
                    ctx.fillStyle = "white"
                    ctx.font = "14px sans-serif"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    ctx.fillText(labels[i], px, py)
                }

                ctx.beginPath()
                ctx.arc(cx, cy, 4, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255, 255, 255, 0.8)"
                ctx.fill()
            }
        }
    }
}
