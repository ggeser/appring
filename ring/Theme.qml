pragma Singleton

// Colours, fonts, motion and the ring's sizes. The palette is Catppuccin
// Mocha.

import QtQuick
import Quickshell

Singleton {
    // ── colour roles ────────────────────────────────────────────────────
    readonly property color text: "#cdd6f4"
    readonly property color dim: "#a6adc8"
    readonly property color muted: "#6c7086"
    readonly property color accent: "#b4a1db"
    readonly property color ok: "#a6e3a1"
    readonly property color warn: "#f9e2af"
    readonly property color error: "#f38ba8"

    readonly property color popup: "#1e1e2e"
    readonly property color popupEdge: "#45475a"

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int fontSmall: 11

    // A state change moves, at rest it is calm; reduced motion turns every
    // duration to 0.
    readonly property bool reducedMotion: Quickshell.env("RING_APP_REDUCED_MOTION") === "1"
    readonly property int fast: reducedMotion ? 0 : 120
    readonly property int easing: Easing.OutCubic

    // ── the ring ────────────────────────────────────────────────────────
    readonly property int radialDeadZone: 64     // px from centre: nothing is active; committing here cancels
    readonly property int radialRingRadius: 220  // moving past this opens a group; also sizes the backdrop
    readonly property int radialIconRadius: 150  // the buttons sit on this circle
    readonly property int radialButtonSize: 48
    readonly property int radialIconSize: 26     // the icon inside a button
    readonly property int radialBadgeSize: 10    // a group's corner badge
    readonly property int radialGlowPad: 10      // the highlighted button's glow, past its own edge
    readonly property real radialHighlightScale: 1.3
    readonly property real radialCornerFraction: 0.18   // "rounded-square" corner, as a fraction of the size
    readonly property real radialSatelliteScale: 0.72    // a satellite ring is this much smaller

    // ── when a satellite (a group's own small ring) closes ──────────────
    // Near the group's own button nothing inside is highlighted: a multiple
    // of that button's own size.
    readonly property real radialSatelliteButtonZoneScale: 1.2
    // It closes once the pointer is back within this fraction of the main
    // ring's radius for that item, measured from the main centre...
    readonly property real radialSatelliteCloseFraction: 0.6
    // ...or once the main angle is this many degrees past the group's own
    // half-sector.
    readonly property real radialSatelliteAngleMargin: 15
}
