#!/usr/bin/env python3
"""A read-only stand-in for Hyprland's IPC, for the off-screen tests.

Hyprland cannot run headless, so the tests draw the ring in a headless sway
and point Quickshell.Hyprland (which the ring uses only to find the focused
monitor) at this instead: the request socket (`.socket.sock`) answers
`j/status`, `j/monitors`, `j/workspaces`, `j/clients`, `j/activeworkspace`
and `j/activewindow` from a fixture; the event socket (`.socket2.sock`)
accepts listeners and stays quiet. Both live in DIR, which the test makes
inside its own runtime dir under a made-up signature, so nothing here can
reach a real Hyprland.

    fake-hyprland.py FIXTURE.json DIR     # DIR = $XDG_RUNTIME_DIR/hypr/<signature>

The fixture:
    {"monitors": [{"name": "HEADLESS-1", "width": 2880, "height": 1800,
                   "x": 0, "y": 0, "scale": 1.2}],
     "focused": "HEADLESS-1"}
"""

import asyncio
import json
import os
import sys


def answers(fixture: dict) -> dict:
    monitors = []
    for i, m in enumerate(fixture["monitors"]):
        monitors.append({
            "id": i, "name": m["name"], "description": f"Test {m['name']}",
            "x": m.get("x", 0), "y": m.get("y", 0),
            "width": m.get("width", 1920), "height": m.get("height", 1080),
            "scale": m.get("scale", 1.0),
            "activeWorkspace": {"id": i + 1, "name": str(i + 1)},
            "specialWorkspace": {"id": 0, "name": ""},
            "focused": m["name"] == fixture.get("focused", fixture["monitors"][0]["name"]),
        })
    workspaces = [{"id": m["id"] + 1, "name": str(m["id"] + 1), "monitor": m["name"],
                   "monitorID": m["id"], "windows": 0, "hasfullscreen": False,
                   "lastwindow": "0x0", "lastwindowtitle": ""} for m in monitors]
    focused = next(w for w, m in zip(workspaces, monitors) if m["focused"])
    return {
        "status": {"configProvider": "hyprlang"},
        "monitors": monitors,
        "workspaces": workspaces,
        "clients": [],
        "activeworkspace": focused,
        "activewindow": {},
    }


async def serve(fixture_path, directory):
    os.makedirs(directory, exist_ok=True)
    with open(fixture_path) as f:
        data = answers(json.load(f))

    async def request(reader, writer):
        req = (await reader.read(65536)).decode().strip().removeprefix("j/")
        writer.write((json.dumps(data[req]) if req in data else "unknown request").encode())
        await writer.drain()
        writer.close()

    async def listen(reader, writer):
        await reader.read()  # until the client goes away

    req = os.path.join(directory, ".socket.sock")
    ev = os.path.join(directory, ".socket2.sock")
    for p in (req, ev):
        if os.path.exists(p):
            os.unlink(p)
    s1 = await asyncio.start_unix_server(request, req)
    s2 = await asyncio.start_unix_server(listen, ev)
    print("ready", flush=True)
    async with s1, s2:
        await asyncio.gather(s1.serve_forever(), s2.serve_forever())


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    asyncio.run(serve(sys.argv[1], sys.argv[2]))
