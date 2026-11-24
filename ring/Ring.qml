// Two RingLayers: the main ring (dimmed while a satellite is open, its
// open group's button kept bright), and the satellite, visible only while
// one is open. Radial.qml decides what is shown; this file only wires it.

import QtQuick

Item {
    id: root
    property var items: []
    property var styles: []
    property int highlighted: -1
    property bool deadZone: true
    property string centerLabel: ""
    property real centreX: width / 2
    property real centreY: height / 2
    property real pointerAngle: 0
    property bool ringVisible: false
    // null, or Radial.qml's satellite frame (see `_openSatellite` there).
    property var satellite: null

    RingLayer {
        anchors.fill: parent
        items: root.items
        styles: root.styles
        highlighted: root.highlighted
        deadZone: root.deadZone
        centerLabel: root.centerLabel
        centreX: root.centreX
        centreY: root.centreY
        pointerAngle: root.pointerAngle
        ringVisible: root.ringVisible
        brightIndex: root.satellite ? root.satellite.parentIndex : -1
        dimOpacity: root.satellite ? 0.4 : 1.0
    }

    RingLayer {
        anchors.fill: parent
        visible: !!root.satellite
        items: root.satellite ? root.satellite.items : []
        styles: root.satellite ? root.satellite.styles : []
        highlighted: root.satellite ? root.satellite.highlighted : -1
        deadZone: root.satellite ? root.satellite.deadZone : true
        centerLabel: ""   // the satellite's own centre goes back up; no caption needed
        centreX: root.satellite ? root.satellite.centreX : 0
        centreY: root.satellite ? root.satellite.centreY : 0
        pointerAngle: root.satellite ? root.satellite.pointerAngle : 0
        ringVisible: root.ringVisible && !!root.satellite
        brightIndex: -1
        dimOpacity: 1.0
    }
}
