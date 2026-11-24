// The radial menu: a full-screen, transparent, keyboard-exclusive layer-shell
// overlay on the focused monitor.
//
// Selection by angle, over the whole screen: the window tracks the pointer
// everywhere, and the active item is the one whose 360/N-wide sector the
// pointer's direction from the centre falls in (0 = up, clockwise;
// `_sliceOf`). A dead zone (Theme.radialDeadZone, a radius around the
// centre) is never active: committing there cancels.
//
// The centre is the cursor: the first real pointer position after `open()`
// becomes the ring's centre for that session, exactly, never clamped. Near
// a corner part of the ring lands off-screen; the angle math still works.
// `centreX`/`centreY` are never animated and are reset to (-1, -1) on
// close, so the next open jumps straight to its own centre.
//
// Groups open as a satellite: a smaller ring centred on the group's own
// button (clamped on-screen), with the main ring still visible and dimmed
// behind it. Selection inside it is the angle from its own centre. Three
// ways open it: resting on the group (`groupTimer`), a click, or moving
// past the main ring's outer radius. Near the group's own button nothing
// inside is highlighted. It closes when the pointer is back near the main
// centre, or when the main angle clearly points at another item, and only
// once that holds for a short grace (`satCloseTimer`), so a jitter never
// closes it. Depth 2 is the limit: a satellite's items do not open further.
//
// Commit: IPC `commit()` (for a key-release bind), releasing the opening key
// inside the window (RING_APP_RELEASE_KEY, Super by default), or a left
// click. Cancel: IPC `cancel()`, Esc, or a right click, always closing
// everything. Committing a leaf runs its `run` argv directly (no shell);
// committing a group opens its satellite; committing in the satellite's
// centre goes back to the main ring.
//
// Config: a JSON file, re-read on every open. `open("")` reads menu.json,
// `open("tools")` reads menu-tools.json, both in RING_APP_CONFIG_DIR
// (default $XDG_CONFIG_HOME/ring-app). The default menu falls back to this
// folder's default.json; a named menu with no file is an empty ring. The
// file is either an array of items or `{"style": {...}, "items": [...]}`.
//
// Look: a global style at the config's top level, a per-item "style" on
// top, a group's style cascading to its satellite's items unless they set
// their own (`_effectiveStyle`). Unknown style keys log one warning each
// per config load, never a crash.
//
// RING_APP_DUMP=1: one `ring-app state <json>` line per change to what is
// shown, highlighted, the dead zone or the satellite, read by the tests
// (tools/check-radial.py).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

PanelWindow {
    id: root

    visible: false
    color: "transparent"
    exclusiveZone: 0
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.namespace: "ring-app"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── settings ──────────────────────────────────────────────────────
    readonly property string _home: Quickshell.env("HOME") ?? ""
    readonly property string _xdgConfig: Quickshell.env("XDG_CONFIG_HOME") ?? ""
    readonly property string _configDirOverride: Quickshell.env("RING_APP_CONFIG_DIR") ?? ""
    readonly property string _configDir: _configDirOverride !== "" ? _configDirOverride
        : ((_xdgConfig !== "" ? _xdgConfig : _home + "/.config") + "/ring-app")
    readonly property string _defaultConfigPath: Quickshell.shellDir + "/default.json"
    readonly property bool _dump: Quickshell.env("RING_APP_DUMP") === "1"

    function _pathFor(name) {
        return _configDir + "/" + (name ? ("menu-" + name + ".json") : "menu.json");
    }

    // The key whose release inside the window commits. The compositor's own
    // bind is not visible from here, so it is a setting.
    readonly property string _releaseKey: Quickshell.env("RING_APP_RELEASE_KEY") ?? "Super"

    // How long resting on a group opens it. The tests raise it far above a
    // synthetic pointer's latency, so "a click opened it" and "it rested
    // open" are told apart.
    readonly property int _restMs: parseInt(Quickshell.env("RING_APP_REST_MS") ?? "250")

    // How long a satellite's close condition must hold before it closes.
    // The tests raise it to prove the delay is real.
    readonly property int _satCloseGraceMs: parseInt(Quickshell.env("RING_APP_CLOSE_MS") ?? "150")

    // ── state ─────────────────────────────────────────────────────────
    property string menuName: ""
    property var items: []        // the main ring
    property var mainStyles: []   // one resolved style per item in `items`, same order
    // null, or the open satellite (see `_openSatellite`). Always replaced
    // as a whole object, so it changes in one step.
    property var satellite: null
    property int highlightedIndex: -1
    property bool deadZone: true
    property real _pointerX: 0
    property real _pointerY: 0
    property real _pointerAngle: 0   // the last angle (the centre's arrow); meaningless in the dead zone
    // The ring's centre: set from the first real pointer position after
    // open(), while `_centreEstablished` is false.
    property real centreX: width / 2
    property real centreY: height / 2
    property bool _centreEstablished: false
    // False until a real pointer position arrives after open(). On the
    // first show the window may not be sized yet, so a guessed centre would
    // be (0, 0); until then it is simply the dead zone.
    property bool _hasPointer: false
    property bool _pastOuterHandled: false

    // The config's global style, not merged with defaults (a satellite's
    // defaults differ, see `_baseStyle`).
    property var _globalStyleRaw: ({})
    readonly property var _styleKeys: ["shape", "cornerRadius", "size", "glowColor", "glowSize", "ringRadius", "captionSize", "backdrop"]
    property var _unknownWarned: null   // a Set, reset on every config parse

    readonly property var _current: (highlightedIndex >= 0 && highlightedIndex < items.length) ? items[highlightedIndex] : null
    readonly property string centerLabel: deadZone || !_current ? "Cancel" : (_current.label ?? "")

    // ── opening / closing ────────────────────────────────────────────
    // Quickshell can list a placeholder screen with no name and no size.
    function _realScreens() {
        return Quickshell.screens.filter(s => !(s.name === "" && s.width === 0 && s.height === 0));
    }

    // The focused monitor on Hyprland; the first screen elsewhere.
    function _focusedScreen() {
        const real = _realScreens();
        if (!real.length)
            return null;
        const focusedName = Hyprland.focusedMonitor?.name ?? "";
        const target = real.find(s => (Hyprland.monitorFor(s)?.name ?? s.name) === focusedName);
        return target ?? real[0];
    }

    function open(name) {
        const target = _focusedScreen();
        if (!target)
            return;
        screen = target;
        menuName = name ?? "";
        satellite = null;
        highlightedIndex = -1;
        deadZone = true;
        _pastOuterHandled = false;
        groupTimer.stop();
        satCloseTimer.stop();
        // Nothing is highlighted until a real pointer position arrives, and
        // every open re-centres on the cursor.
        _hasPointer = false;
        _centreEstablished = false;
        visible = true;
        _reloadConfig();
        Qt.callLater(() => content.forceActiveFocus());
    }

    function toggle(name) {
        if (visible)
            cancel();
        else
            open(name);
    }

    function cancel() {
        _close();
    }

    function commit() {
        if (!visible)
            return;
        if (satellite) {
            if (satellite.deadZone || satellite.highlighted < 0) {
                // On the group's own button: back to the main ring, not a
                // cancel of the whole menu.
                satellite = null;
                satCloseTimer.stop();
                _dumpState();
                return;
            }
            _run(satellite.items[satellite.highlighted]);
            _close();
            return;
        }
        if (deadZone || !_current) {
            cancel();
            return;
        }
        if (_current.items) {
            _openSatellite(highlightedIndex);
            return;
        }
        _run(_current);
        _close();
    }

    function _close() {
        visible = false;
        items = [];
        mainStyles = [];
        satellite = null;
        highlightedIndex = -1;
        deadZone = true;
        groupTimer.stop();
        satCloseTimer.stop();
        // An off-screen sentinel, so nothing is ever drawn from a stale
        // centre between sessions.
        centreX = -1;
        centreY = -1;
        _centreEstablished = false;
        _hasPointer = false;
        _dumpState();
    }

    // Runs an item's argv as it is: no shell, so no quoting problems. The
    // first element is looked up on PATH.
    function _run(item) {
        if (!item || !Array.isArray(item.run) || !item.run.length || !item.run[0])
            return;
        Quickshell.execDetached(item.run.map(String));
    }

    // ── the satellite ring ────────────────────────────────────────────

    // Where the main-ring button at `index` sits, by its own ringRadius.
    function _mainButtonPos(index) {
        const angleRad = (index * (360 / items.length)) * Math.PI / 180;
        const r = mainStyles[index]?.ringRadius ?? Theme.radialIconRadius;
        return { x: centreX + r * Math.sin(angleRad), y: centreY - r * Math.cos(angleRad) };
    }

    // Past this distance a group opens on its own: the button's ringRadius
    // plus the same margin as Theme's default outer radius.
    function _outerThreshold(ringRadius) {
        return ringRadius + (Theme.radialRingRadius - Theme.radialIconRadius);
    }

    function _openSatellite(index) {
        const item = items[index];
        if (!item || !Array.isArray(item.items) || !item.items.length)
            return;
        const pos = _mainButtonPos(index);
        const groupStyleRaw = (item.style && typeof item.style === "object") ? item.style : {};
        const styles = item.items.map(child => _effectiveStyle(child, true, groupStyleRaw));
        const margin = Theme.radialDeadZone + Math.max(...styles.map(s => s.ringRadius + s.size)) + 20;
        // The main ring's resolved style for the button that opened this
        // satellite, kept on the frame so every later check uses the same
        // numbers.
        const mainStyle = mainStyles[index] ?? _baseStyle(false);
        const mainRingRadius = mainStyle.ringRadius ?? Theme.radialIconRadius;
        const sliceWidth = items.length > 0 ? 360 / items.length : 360;
        satellite = {
            parentIndex: index,
            items: item.items,
            styles: styles,
            groupStyleRaw: groupStyleRaw,
            // Clamped on-screen, unlike the main centre: the group button's
            // spot can land off-screen near an edge.
            centreX: Math.max(margin, Math.min(width - margin, pos.x)),
            centreY: Math.max(margin, Math.min(height - margin, pos.y)),
            highlighted: -1,
            deadZone: true,
            pointerAngle: 0,
            // Near the group's own button: nothing inside is highlighted.
            buttonRadius: mainStyle.size * Theme.radialSatelliteButtonZoneScale,
            // Closes when back within this distance of the main centre...
            closeRadius: mainRingRadius * Theme.radialSatelliteCloseFraction,
            // ...or when the main angle is this far from the group's own.
            parentAngle: index * sliceWidth,
            closeAngleThreshold: sliceWidth / 2 + Theme.radialSatelliteAngleMargin
        };
        highlightedIndex = index;
        _pastOuterHandled = false;
        groupTimer.stop();
        satCloseTimer.stop();
        _dumpState();
    }

    // ── style cascade ─────────────────────────────────────────────────

    function _baseStyle(inSatellite) {
        const scale = inSatellite ? Theme.radialSatelliteScale : 1;
        return {
            shape: "rounded-square",
            cornerRadius: Theme.radialCornerFraction,
            size: Math.round(Theme.radialButtonSize * scale),
            glowColor: "accent",
            glowSize: Math.round(Theme.radialGlowPad * scale),
            ringRadius: Math.round(Theme.radialIconRadius * scale),
            captionSize: Math.round(Theme.fontSmall * scale),
            backdrop: true
        };
    }

    // Only the known keys `override` actually sets replace `base`'s.
    function _mergeStyle(base, override) {
        if (!override || typeof override !== "object")
            return base;
        const out = Object.assign({}, base);
        for (const k of _styleKeys) {
            if (Object.prototype.hasOwnProperty.call(override, k))
                out[k] = override[k];
        }
        return out;
    }

    function _warnUnknownKeys(obj, context) {
        if (!obj || typeof obj !== "object")
            return;
        for (const k of Object.keys(obj)) {
            if (_styleKeys.indexOf(k) === -1 && !_unknownWarned.has(k)) {
                _unknownWarned.add(k);
                console.warn("ring-app: unknown style key \"" + k + "\" (" + context + "), ignored");
            }
        }
    }

    // Defaults, then the global style, then (in a satellite) the opening
    // group's style, then the item's own.
    function _effectiveStyle(item, inSatellite, groupStyleRaw) {
        let s = _baseStyle(inSatellite);
        s = _mergeStyle(s, _globalStyleRaw);
        if (inSatellite && groupStyleRaw)
            s = _mergeStyle(s, groupStyleRaw);
        s = _mergeStyle(s, item && item.style);
        return s;
    }

    // ── angle math ────────────────────────────────────────────────────

    // 0deg = up, clockwise: atan2(dx, -dy) measures from "up", positive to
    // the right. Used by the main ring and the satellite alike.
    function _sliceOf(dx, dy, count) {
        const angle = (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360;
        const sliceWidth = 360 / count;
        return { angle: angle, idx: Math.floor(((angle + sliceWidth / 2) % 360) / sliceWidth) };
    }

    function _recomputeHighlight() {
        if (!_hasPointer) {
            if (highlightedIndex !== -1)
                highlightedIndex = -1;
            deadZone = true;
            _dumpState();
            return;
        }
        if (width <= 0 || height <= 0)
            return;

        // The main ring's highlight, computed even while a satellite is
        // open: the satellite's close check needs it.
        const mdx = _pointerX - centreX;
        const mdy = _pointerY - centreY;
        const mdist = Math.hypot(mdx, mdy);
        const mainDeadZone = mdist < Theme.radialDeadZone;
        let mainIdx = -1;
        let mainAngle = _pointerAngle;
        if (!mainDeadZone && items.length > 0) {
            const r = _sliceOf(mdx, mdy, items.length);
            mainIdx = r.idx;
            mainAngle = r.angle;
        }

        if (satellite) {
            const sdx = _pointerX - satellite.centreX;
            const sdy = _pointerY - satellite.centreY;
            const sdist = Math.hypot(sdx, sdy);
            // Near the group's own button: nothing inside is highlighted,
            // but the satellite stays open (the pointer is right here the
            // moment it opens).
            const nearButton = sdist < satellite.buttonRadius;

            // Close only when back toward the main centre, or when the main
            // angle clearly reads as another item (past the group's sector
            // plus a margin).
            const towardCentre = mdist < satellite.closeRadius;
            let angleDiff = Math.abs(mainAngle - satellite.parentAngle);
            if (angleDiff > 180)
                angleDiff = 360 - angleDiff;
            const differentItem = angleDiff > satellite.closeAngleThreshold;
            const shouldClose = towardCentre || differentItem;

            // Only `satCloseTimer` closes it; the timer stops as soon as the
            // condition stops holding.
            if (shouldClose) {
                if (!satCloseTimer.running)
                    satCloseTimer.start();
            } else {
                satCloseTimer.stop();
            }

            if (!shouldClose) {
                let idx = -1;
                let angle = satellite.pointerAngle;
                if (!nearButton) {
                    const r = _sliceOf(sdx, sdy, satellite.items.length);
                    idx = r.idx;
                    angle = r.angle;
                }
                if (idx !== satellite.highlighted || nearButton !== satellite.deadZone || angle !== satellite.pointerAngle)
                    satellite = Object.assign({}, satellite, { highlighted: idx, deadZone: nearButton, pointerAngle: angle });
                // The main ring keeps showing this group while its
                // satellite is open.
                if (highlightedIndex !== satellite.parentIndex)
                    highlightedIndex = satellite.parentIndex;
                if (deadZone)
                    deadZone = false;
                _pointerAngle = mainAngle;
                _dumpState();
                return;
            }
            // Closing: the satellite stays as it is until the timer fires.
            _pointerAngle = mainAngle;
            _dumpState();
            return;
        }

        // The main ring alone.
        deadZone = mainDeadZone;
        if (deadZone || items.length === 0) {
            if (highlightedIndex !== -1) {
                highlightedIndex = -1;
                groupTimer.stop();
            }
            _dumpState();
            return;
        }
        _pointerAngle = mainAngle;
        if (mainIdx !== highlightedIndex) {
            highlightedIndex = mainIdx;
            _pastOuterHandled = false;
            groupTimer.restart();
        }
        const cur = items[mainIdx];
        const ringRadius = mainStyles[mainIdx]?.ringRadius ?? Theme.radialIconRadius;
        if (cur && cur.items && mdist > _outerThreshold(ringRadius) && !_pastOuterHandled) {
            _pastOuterHandled = true;
            _openSatellite(mainIdx);
            return;   // _openSatellite already dumped
        }
        _dumpState();
    }

    // ── config loading ────────────────────────────────────────────────

    // Keeps only objects with a string `label`, one level of children deep
    // (a satellite's items do not open further), warning about unknown
    // style keys on the way.
    function _sanitizeItems(rawItems, context) {
        if (!Array.isArray(rawItems))
            return [];
        return rawItems.filter(it => it && typeof it.label === "string").map(it => {
            if (it.style && typeof it.style === "object")
                _warnUnknownKeys(it.style, "item \"" + it.label + "\"" + context);
            if (Array.isArray(it.items)) {
                const children = it.items.filter(c => c && typeof c.label === "string").map(c => {
                    if (c.style && typeof c.style === "object")
                        _warnUnknownKeys(c.style, "item \"" + c.label + "\" (child of \"" + it.label + "\")");
                    return c;
                });
                return Object.assign({}, it, { items: children });
            }
            return it;
        });
    }

    // A plain array (no global style), or `{"style": {...}, "items": [...]}`.
    function _parseConfig(text) {
        _unknownWarned = new Set();
        try {
            const data = JSON.parse(text);
            let styleRaw = {};
            let rawItems = [];
            if (Array.isArray(data)) {
                rawItems = data;
            } else if (data && typeof data === "object") {
                styleRaw = (data.style && typeof data.style === "object") ? data.style : {};
                rawItems = Array.isArray(data.items) ? data.items : [];
            }
            _warnUnknownKeys(styleRaw, "global style");
            return { styleRaw: styleRaw, items: _sanitizeItems(rawItems, "") };
        } catch (e) {
            console.warn("ring-app: unreadable config", e);
            return { styleRaw: {}, items: [] };
        }
    }

    function _applyConfig(parsed) {
        _globalStyleRaw = parsed.styleRaw;
        items = parsed.items;
        mainStyles = items.map(it => _effectiveStyle(it, false, null));
        satellite = null;
        highlightedIndex = -1;
        deadZone = true;
        _pastOuterHandled = false;
        _recomputeHighlight();
        _dumpState();
    }

    function _reloadConfig() {
        const path = _pathFor(menuName);
        if (configFile.path === path)
            configFile.reload();
        else
            configFile.path = path;
    }

    FileView {
        id: configFile
        printErrors: false // a missing file is not an error
        onLoaded: root._applyConfig(root._parseConfig(text()))
        onLoadFailed: {
            // The default menu falls back to default.json; a named menu
            // with no file is an empty ring.
            if (root.menuName === "")
                root._applyConfig(root._parseConfig(defaultConfigFile.text()));
            else
                root._applyConfig({ styleRaw: {}, items: [] });
        }
    }

    FileView {
        id: defaultConfigFile
        path: root._defaultConfigPath
        printErrors: false
    }

    // ── state dump, for the tests ─────────────────────────────────────

    function _styleDump(s) {
        return {
            shape: s.shape, cornerRadius: s.cornerRadius, size: s.size,
            glowColor: s.glowColor, glowSize: s.glowSize, ringRadius: s.ringRadius,
            captionSize: s.captionSize, backdrop: s.backdrop
        };
    }

    function _itemsDump(its, styles) {
        return its.map((it, i) => ({
            label: it.label,
            icon: it.icon ?? "",
            kind: it.items ? "group" : "leaf",
            style: _styleDump(styles[i] ?? _baseStyle(false))
        }));
    }

    // Called by hand at the end of every function that changes several of
    // these properties together, never from a property-change handler:
    // a handler would fire after the first property changes and log a
    // half-updated state.
    function _dumpState() {
        if (!root._dump)
            return;
        console.info("ring-app state " + JSON.stringify({
            visible: root.visible,
            items: root._itemsDump(root.items, root.mainStyles),
            highlighted: root.highlightedIndex,
            deadZone: root.deadZone,
            centreX: Math.round(root.centreX),
            centreY: Math.round(root.centreY),
            satellite: root.satellite ? {
                parentIndex: root.satellite.parentIndex,
                items: root._itemsDump(root.satellite.items, root.satellite.styles),
                highlighted: root.satellite.highlighted,
                deadZone: root.satellite.deadZone,
                centreX: Math.round(root.satellite.centreX),
                centreY: Math.round(root.satellite.centreY)
            } : null
        }));
    }

    // Its screen going away while open closes it.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.visible && !root._realScreens().includes(root.screen))
                root.cancel();
        }
    }

    IpcHandler {
        target: "ring"
        function open(name: string): void { root.open(name); }
        function commit(): void { root.commit(); }
        function cancel(): void { root.cancel(); }
        function toggle(name: string): void { root.toggle(name); }
    }

    Timer {
        id: groupTimer
        interval: root._restMs
        onTriggered: {
            if (root.satellite)
                return;
            const cur = root._current;
            if (cur && cur.items && !root._pastOuterHandled) {
                root._pastOuterHandled = true;
                root._openSatellite(root.highlightedIndex);
            }
        }
    }

    // The satellite's close grace: started when a close condition first
    // holds, stopped when it stops holding. When it fires, the highlight is
    // recomputed at once, so the main ring takes over without another move.
    Timer {
        id: satCloseTimer
        interval: root._satCloseGraceMs
        onTriggered: {
            if (!root.satellite)
                return;
            root.satellite = null;
            root._pastOuterHandled = false;
            groupTimer.stop();
            root._recomputeHighlight();
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                root.cancel();
            }
        }
        Keys.onReleased: event => {
            if (root._matchesReleaseKey(event.key)) {
                event.accepted = true;
                root.commit();
            }
        }

        Ring {
            anchors.fill: parent
            items: root.items
            styles: root.mainStyles
            highlighted: root.highlightedIndex
            deadZone: root.deadZone
            centerLabel: root.centerLabel
            centreX: root.centreX
            centreY: root.centreY
            pointerAngle: root._pointerAngle
            ringVisible: root._centreEstablished
            satellite: root.satellite
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPositionChanged: mouse => {
                root._pointerX = mouse.x;
                root._pointerY = mouse.y;
                if (!root._centreEstablished) {
                    // The first position this session is the centre, exactly.
                    root.centreX = mouse.x;
                    root.centreY = mouse.y;
                    root._centreEstablished = true;
                    root._dumpState();
                }
                root._hasPointer = true;
                root._recomputeHighlight();
            }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    root.cancel();
                    return;
                }
                root.commit();
            }
        }
    }

    function _matchesReleaseKey(key) {
        switch (root._releaseKey) {
        case "Alt":
            return key === Qt.Key_Alt;
        case "Ctrl":
            return key === Qt.Key_Control;
        case "Shift":
            return key === Qt.Key_Shift;
        default:
            return key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta;
        }
    }
}
