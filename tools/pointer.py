#!/usr/bin/env python3
"""A virtual pointer that stays: clicks and hovers for the gallery.

wlrctl makes a pointer per command and drops it at once, so between two
commands the seat has none and the compositor throws presses away. This
keeps one zwlr_virtual_pointer_v1 for the whole scene and reads commands,
one per line, from stdin:

    move X Y          absolute, in layout coordinates (logical pixels)
    click left|middle|right [HOLD]
                      press, wait HOLD seconds (default 0.05), release
    scroll DY         wheel notches (positive: down), in one wheel event
    flick DY          as many one-notch wheel events, back to back (a fast
                      flick of a mouse wheel: one event per notch)

    pointer.py WLR_PROTOCOLS_DIR WAYLAND_XML LAYOUT_W LAYOUT_H < commands

It connects to $WAYLAND_DISPLAY, which the gallery has already checked is
its own headless sway.
"""

import os
import sys
import tempfile
import time

BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}  # BTN_* from linux/input-event-codes.h


def generate(proto_dir, wayland_xml):
    """Python bindings for the core protocol and the virtual pointer, in a
    throwaway package (pywayland-scanner's command line asks pkg-config
    first, which a plain nix shell has not got)."""
    out = tempfile.mkdtemp(prefix="gallery-proto-")
    pkg = os.path.join(out, "galleryproto")
    xml = os.path.join(proto_dir, "unstable", "wlr-virtual-pointer-unstable-v1.xml")
    from pywayland.scanner import Protocol

    protocols = [Protocol.parse_file(f) for f in (wayland_xml, xml)]
    imports = {i.name: p.name for p in protocols for i in p.interface}
    os.makedirs(pkg)
    for p in protocols:
        p.output(pkg, imports)
    open(os.path.join(pkg, "__init__.py"), "a").close()
    sys.path.insert(0, out)


def main():
    proto, wayland_xml, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    generate(proto, wayland_xml)
    from galleryproto.wayland import WlSeat
    from galleryproto.wlr_virtual_pointer_unstable_v1 import ZwlrVirtualPointerManagerV1
    from pywayland.client import Display

    display = Display()
    display.connect()
    found = {}

    def on_global(registry, name, interface, version):
        if interface == "zwlr_virtual_pointer_manager_v1":
            found["mgr"] = registry.bind(name, ZwlrVirtualPointerManagerV1, 1)
        elif interface == "wl_seat" and "seat" not in found:
            found["seat"] = registry.bind(name, WlSeat, 1)

    registry = display.get_registry()
    registry.dispatcher["global"] = on_global
    display.roundtrip()
    pointer = found["mgr"].create_virtual_pointer(found["seat"])
    display.roundtrip()

    def ms():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    print("ready", flush=True)
    for line in sys.stdin:
        cmd = line.split()
        if not cmd:
            continue
        if cmd[0] == "move":
            pointer.motion_absolute(ms(), int(cmd[1]), int(cmd[2]), w, h)
            pointer.frame()
        elif cmd[0] == "click":
            b = BUTTONS[cmd[1]]
            pointer.button(ms(), b, 1)
            pointer.frame()
            display.roundtrip()
            time.sleep(float(cmd[2]) if len(cmd) > 2 else 0.05)
            pointer.button(ms(), b, 0)
            pointer.frame()
        elif cmd[0] == "scroll":
            n = int(cmd[1])
            pointer.axis_source(0)  # wheel
            pointer.axis_discrete(ms(), 0, 15.0 * n, n)
            pointer.frame()
        elif cmd[0] == "flick":
            n = int(cmd[1])
            step = 1 if n > 0 else -1
            for _ in range(abs(n)):
                pointer.axis_source(0)
                pointer.axis_discrete(ms(), 0, 15.0 * step, step)
                pointer.frame()
        display.roundtrip()


if __name__ == "__main__":
    main()
