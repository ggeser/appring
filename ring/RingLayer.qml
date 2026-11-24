// Drawing only: one ring's buttons, backdrop and centre indicator. Used
// twice (Ring.qml): for the main ring and for a satellite. It draws "a ring
// of items with resolved styles, a highlight, a centre and a direction",
// exactly what Radial.qml hands it.
//
// Buttons sit on an invisible circle. `style.shape` is "rounded-square"
// (the default; corner radius `style.cornerRadius` as a fraction of the
// button's size) or "circle"; the glow follows the same shape. Every size
// and colour a button uses comes from its own resolved style
// (`styles[index]`, Radial.qml's cascade).
//
// The highlighted button grows and glows; a small centre disc has a little
// arrow pointing at the current direction (hidden in the dead zone). Every
// item's caption is always shown under its button, the highlighted one
// brighter and bold; a group's caption gets a trailing "›" and its button
// a corner badge. `brightIndex`/`dimOpacity` let Ring.qml dim the other
// main-ring buttons while a satellite is open.
//
// Colours are Theme's roles; `style.glowColor` picks one by name
// (`_roleColor`), an unknown name falls back to `accent`.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets

Item {
    id: ringLayer
    property var items: []
    property var styles: []        // parallel to `items`: one resolved style object each
    property int highlighted: -1
    property bool deadZone: true
    property string centerLabel: ""
    property real centreX: width / 2
    property real centreY: height / 2
    property real pointerAngle: 0
    // False until this ring has a real centre: the layer stays invisible
    // until then, so it never jumps once the centre lands.
    property bool ringVisible: false
    // The one index kept at full opacity (the open group's button while
    // its satellite is up); -1: none.
    property int brightIndex: -1
    // Applied to every button except `brightIndex`; 1.0: nothing dimmed.
    property real dimOpacity: 1.0

    function _roleColor(name) {
        switch (name) {
        case "accent": return Theme.accent;
        case "warn": return Theme.warn;
        case "error": return Theme.error;
        case "ok": return Theme.ok;
        case "muted": return Theme.muted;
        case "dim": return Theme.dim;
        case "text": return Theme.text;
        default: return Theme.accent;
        }
    }

    // A soft backdrop around this ring only, never a full-screen dim: a
    // radial gradient fading to transparent, sized from the largest
    // ringRadius of this layer's items plus a 70px margin. The shape is a
    // square; the round look comes from the gradient.
    Shape {
        id: backdrop
        readonly property real _maxRing: ringLayer.styles.length ? Math.max(...ringLayer.styles.map(s => s.ringRadius ?? Theme.radialIconRadius)) : Theme.radialIconRadius
        readonly property real d: (_maxRing + 70) * 2
        x: ringLayer.centreX - d / 2
        y: ringLayer.centreY - d / 2
        width: d
        height: d
        opacity: ringLayer.ringVisible ? 1 : 0
        // Animate in, snap out: closing (ringVisible -> false) disables the
        // Behavior for that change, so no fade lingers at the old centre
        // when the next open lands somewhere else.
        Behavior on opacity {
            enabled: ringLayer.ringVisible
            NumberAnimation { duration: Theme.fast }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: backdrop.width / 2
                centerY: backdrop.height / 2
                centerRadius: backdrop.width / 2
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(Theme.popup.r, Theme.popup.g, Theme.popup.b, 0.6) }
                GradientStop { position: 0.6; color: Qt.rgba(Theme.popup.r, Theme.popup.g, Theme.popup.b, 0.32) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.popup.r, Theme.popup.g, Theme.popup.b, 0) }
            }
            startX: 0
            startY: 0
            PathLine { x: backdrop.width; y: 0 }
            PathLine { x: backdrop.width; y: backdrop.height }
            PathLine { x: 0; y: backdrop.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Text {
        visible: ringLayer.items.length === 0 && ringLayer.ringVisible
        anchors.centerIn: parent
        text: "No items in this menu"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: ringLayer.items
        delegate: Item {
            id: button
            required property var modelData
            required property int index
            readonly property var _style: ringLayer.styles[index] ?? ({})
            readonly property real _angleDeg: index * (360 / ringLayer.items.length)
            readonly property real _angleRad: _angleDeg * Math.PI / 180
            readonly property bool _active: index === ringLayer.highlighted && !ringLayer.deadZone
            readonly property bool _isGroup: !!button.modelData.items
            readonly property real _ringRadius: _style.ringRadius ?? Theme.radialIconRadius
            readonly property real _size: _style.size ?? Theme.radialButtonSize
            readonly property real _glowPad: _style.glowSize ?? Theme.radialGlowPad
            readonly property real _iconSize: Math.round(_size * (Theme.radialIconSize / Theme.radialButtonSize))
            readonly property real _captionSize: _style.captionSize ?? Theme.fontSmall
            readonly property color _glowColor: ringLayer._roleColor(_style.glowColor)
            readonly property real _dim: index === ringLayer.brightIndex ? 1 : ringLayer.dimOpacity

            // The corner radius for a rectangle of `sizePx` (the button, or
            // a larger glow rectangle) in this button's shape.
            function radiusFor(sizePx) {
                return (_style.shape === "circle") ? sizePx / 2 : sizePx * (_style.cornerRadius ?? Theme.radialCornerFraction);
            }

            width: _size
            height: width
            x: ringLayer.centreX + _ringRadius * Math.sin(_angleRad) - width / 2
            y: ringLayer.centreY - _ringRadius * Math.cos(_angleRad) - height / 2
            scale: (ringLayer.ringVisible ? (_active ? Theme.radialHighlightScale : 1) : 0.4)
            opacity: (ringLayer.ringVisible ? (ringLayer.deadZone ? 0.85 : (_active ? 1 : 0.6)) : 0) * _dim
            // Animate in, snap out: see the backdrop's own comment above.
            Behavior on scale {
                enabled: ringLayer.ringVisible
                NumberAnimation { duration: Theme.fast; easing.type: Theme.easing }
            }
            Behavior on opacity {
                enabled: ringLayer.ringVisible
                NumberAnimation { duration: Theme.fast }
            }

            // The highlighted button's glow, behind it: two soft layers.
            Rectangle {
                visible: button._active
                anchors.centerIn: parent
                width: parent.width + button._glowPad * 4
                height: width
                radius: button.radiusFor(width)
                color: button._glowColor
                opacity: 0.14
            }
            Rectangle {
                visible: button._active
                anchors.centerIn: parent
                width: parent.width + button._glowPad * 2
                height: width
                radius: button.radiusFor(width)
                color: button._glowColor
                opacity: 0.3
            }
            Rectangle {
                anchors.fill: parent
                radius: button.radiusFor(width)
                color: Theme.popup
                border.width: button._active ? 2 : 1
                border.color: button._active ? button._glowColor : Theme.popupEdge
                Behavior on border.color {
                    ColorAnimation { duration: Theme.fast }
                }
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: button._iconSize
                source: button.modelData.icon ? Quickshell.iconPath(button.modelData.icon, true) : ""
                asynchronous: true
            }
            // A group's corner badge, top-right.
            Rectangle {
                visible: button._isGroup
                width: Theme.radialBadgeSize
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -2
                anchors.topMargin: -2
                color: Theme.warn
                border.width: 1
                border.color: Theme.popup
            }

            // The caption, always shown. Its opacity is computed on its own,
            // not from `button.opacity`, which would dim it twice.
            Text {
                anchors.top: parent.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                text: (button.modelData.label ?? "") + (button._isGroup ? " \u203a" : "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: button._captionSize
                font.bold: button._active
                horizontalAlignment: Text.AlignHCenter
                opacity: (ringLayer.ringVisible ? (button._active ? 1 : 0.8) : 0) * button._dim
            }
        }
    }

    // The centre indicator: a small disc, and a little arrow just outside
    // it pointing at the current direction (hidden in the dead zone).
    Item {
        id: centre
        width: 30
        height: 30
        x: ringLayer.centreX - width / 2
        y: ringLayer.centreY - height / 2
        scale: ringLayer.ringVisible ? 1 : 0.4
        opacity: ringLayer.ringVisible ? 1 : 0
        // Animate in, snap out: see the backdrop's own comment above.
        Behavior on scale {
            enabled: ringLayer.ringVisible
            NumberAnimation { duration: Theme.fast; easing.type: Theme.easing }
        }
        Behavior on opacity {
            enabled: ringLayer.ringVisible
            NumberAnimation { duration: Theme.fast }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.popup
            border.width: 2
            border.color: Theme.popupEdge
        }

        // A small triangle just past the disc's edge, rotated to
        // pointerAngle.
        Item {
            id: needleHolder
            readonly property real _rad: ringLayer.pointerAngle * Math.PI / 180
            readonly property real _offset: centre.width / 2 + 9
            width: 14
            height: 14
            x: centre.width / 2 + _offset * Math.sin(_rad) - width / 2
            y: centre.height / 2 - _offset * Math.cos(_rad) - height / 2
            rotation: ringLayer.pointerAngle
            visible: !ringLayer.deadZone

            Canvas {
                id: needle
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.beginPath();
                    ctx.moveTo(width / 2, 0);
                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                    ctx.closePath();
                    ctx.fillStyle = Theme.accent;
                    ctx.fill();
                }
                Component.onCompleted: requestPaint()
            }
        }
    }

    // "Cancel", only in the dead zone (a satellite passes ""): once an
    // item is highlighted, its caption says what committing does.
    Text {
        anchors.horizontalCenter: centre.horizontalCenter
        anchors.top: centre.bottom
        anchors.topMargin: 10
        opacity: (ringLayer.ringVisible && ringLayer.deadZone && ringLayer.centerLabel !== "") ? 1 : 0
        text: ringLayer.centerLabel
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        horizontalAlignment: Text.AlignHCenter
        // Animate in, snap out: see the backdrop's own comment above.
        Behavior on opacity {
            enabled: ringLayer.ringVisible
            NumberAnimation { duration: Theme.fast }
        }
    }
}
