import AppringCore
import Foundation

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        fputs("FAIL \(message)\n", stderr)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    expect(actual == expected, "\(message): \(actual) != \(expected)")
}

func expectNear(_ actual: Double, _ expected: Double, _ message: String) {
    expect(abs(actual - expected) < 0.001, "\(message): \(actual) != \(expected)")
}

func opened(gap: Double = 0) -> Session {
    var session = Session()
    var appearance = Appearance()
    appearance.sliceGap = gap
    session.openMenu(
        items: [
            Item(label: "Tools", items: [
                Item(label: "Hello", run: ["say", "hi"]),
                Item(label: "Calc", run: ["open", "-a", "Calculator"]),
            ]),
            Item(label: "Terminal", run: ["open", "-a", "Terminal"]),
            Item(label: "Finder", run: ["open", "-a", "Finder"]),
            Item(label: "Safari", run: ["open", "-a", "Safari"]),
        ],
        style: [:],
        centre: Vec(400, 400),
        pointer: Vec(400, 400),
        screen: Vec(800, 800),
        appearance: appearance,
        now: 0
    )
    return session
}

expectEqual(sliceOf(dx: 0, dy: -10, count: 4, gap: 0).index, 0, "up")
expectEqual(sliceOf(dx: 10, dy: 0, count: 4, gap: 0).index, 1, "right")
expectEqual(sliceOf(dx: 0, dy: 10, count: 4, gap: 0).index, 2, "down")
expectEqual(sliceOf(dx: -10, dy: 0, count: 4, gap: 0).index, 3, "left")

expectEqual(sliceOf(dx: 100, dy: -100, count: 4, gap: 0).index, 1, "boundary")
expectEqual(sliceOf(dx: 100, dy: -100, count: 4, gap: 0.5).index, -1, "gap")

let top = buttonCenter(index: 0, count: 4, centre: Vec(10, 10), radius: 5)
expectNear(top.x, 10, "button x")
expectNear(top.y, 5, "button y")

var centre = opened()
expect(centre.deadZone, "opens in the dead zone")
expectEqual(centre.commit(), .closed, "centre commit")
expect(!centre.open, "centre commit closes")

var leaf = opened()
leaf.pointer(Vec(550, 400), now: 0)
expectEqual(leaf.highlighted, 1, "right slice")
expectEqual(leaf.commit(), .ran(["open", "-a", "Terminal"]), "leaf run")
expect(!leaf.open, "leaf closes")

var rest = opened()
rest.pointer(Vec(400, 250), now: 0)
expect(rest.satellite == nil, "group waits")
rest.advance(now: 249)
expect(rest.satellite == nil, "group still waits")
rest.advance(now: 250)
expectEqual(rest.satellite?.parentIndex ?? -1, 0, "group opens on rest")
expect(rest.open, "rest keeps the ring")

var outer = opened()
outer.pointer(Vec(400, 200), now: 0)
expectEqual(outer.satellite?.parentIndex ?? -1, 0, "group opens past the ring")

var child = opened()
child.pointer(Vec(400, 200), now: 0)
let childCentreY = child.satellite?.centreY ?? 0
child.pointer(Vec(400, childCentreY - 100), now: 10)
expectEqual(child.satellite?.highlighted ?? -2, 0, "satellite child")
expectEqual(child.commit(), .ran(["say", "hi"]), "satellite run")

var back = opened()
back.pointer(Vec(400, 200), now: 0)
let backCentre = Vec(back.satellite?.centreX ?? 0, back.satellite?.centreY ?? 0)
back.pointer(backCentre, now: 10)
expectEqual(back.commit(), .back, "satellite centre")
expect(back.satellite == nil, "back to main")
expect(back.open, "main stays open")

var gap = opened(gap: 0.5)
gap.pointer(Vec(500, 300), now: 0)
expect(!gap.deadZone, "gap is not the centre")
expectEqual(gap.highlighted, -1, "gap selects nothing")
expectEqual(gap.commit(), .closed, "gap commit")

var cancelled = opened()
cancelled.pointer(Vec(550, 400), now: 0)
cancelled.cancel()
expect(!cancelled.open, "cancel")

var grace = opened()
grace.pointer(Vec(400, 200), now: 0)
expect(grace.satellite != nil, "grace starts open")
grace.pointer(Vec(400, 350), now: 20)
expect(grace.satellite != nil, "grace holds")
grace.advance(now: 20 + 149)
expect(grace.satellite != nil, "grace not yet")
grace.advance(now: 20 + 150)
expect(grace.satellite == nil, "grace elapsed")
expect(grace.open, "main stays after grace")

let json = """
{"style":{"size":80,"backdrop":true,"nope":1},"items":[
  {"label":"A","run":["echo",1]},
  {"label":"G","items":[{"label":"C","items":[{"label":"too deep"}]}]},
  {"run":["x"]}
]}
""".data(using: .utf8)!
let menu = parseMenu(json)
expectEqual(menu.items.map(\.label), ["A", "G"], "labels")
expectEqual(menu.items[0].run, ["echo", "1"], "run strings")
expectEqual(menu.items[1].items.map(\.label), ["C"], "children")
expect(menu.items[1].items[0].items.isEmpty, "one level")
expect(menu.warnings.contains { $0.contains("nope") }, "unknown style")
var styled = Session()
styled.openMenu(items: menu.items, style: menu.style, centre: Vec(0, 0), pointer: Vec(0, 0), screen: Vec(800, 800), appearance: Appearance(), now: 0)
expectEqual(styled.styles[0].size, 80, "style size")
expect(styled.styles[0].backdrop, "style backdrop")

let legacy = resolveConfigDirectory(env: [:], home: "/Users/me", exists: { $0 == "/Users/me/.config/ring-app" })
expectEqual(legacy.path, "/Users/me/.config/ring-app", "legacy dir")
expect(legacy.legacy, "legacy flag")
let newer = resolveConfigDirectory(env: [:], home: "/Users/me", exists: { $0.hasSuffix("/appring") || $0.hasSuffix("/ring-app") })
expectEqual(newer.path, "/Users/me/.config/appring", "new dir wins")
expect(!newer.legacy, "not legacy")
let override = resolveConfigDirectory(env: ["APPRING_CONFIG_DIR": "/opt/cfg", "RING_APP_CONFIG_DIR": "/old"], home: "/Users/me", exists: { _ in true })
expectEqual(override.path, "/opt/cfg", "override")
let xdg = resolveConfigDirectory(env: ["XDG_CONFIG_HOME": "/xdg"], home: "/Users/me", exists: { _ in false })
expectEqual(xdg.path, "/xdg/appring", "xdg")
expectEqual(menuFileName(""), "menu.json", "default menu file")
expectEqual(menuFileName("tools"), "menu-tools.json", "named menu")
expect(menuFileName("../secret") == nil, "reject dotdot")
expect(menuFileName("a/b") == nil, "reject slash")

expectEqual(resolveExecutable(argv0: "open", path: "/usr/bin:/bin", isExecutable: { $0 == "/usr/bin/open" }), "/usr/bin/open", "path lookup")
expect(resolveExecutable(argv0: "missing", path: "/usr/bin", isExecutable: { _ in false }) == nil, "missing command")
expectEqual(resolveExecutable(argv0: "/bin/echo", path: "", isExecutable: { $0 == "/bin/echo" }), "/bin/echo", "absolute")
expect(commandSearchPath("/usr/bin").contains("/opt/homebrew/bin"), "homebrew on path")
expectEqual(commandSearchPath("/opt/homebrew/bin:/usr/bin").components(separatedBy: "/opt/homebrew/bin").count, 2, "homebrew once")

let appearance = loadAppearance(
    data: #"{"scale":9,"labels":"nope","deadZone":-4}"#.data(using: .utf8),
    env: ["RING_APP_REST_MS": "40", "APPRING_CLOSE_MS": "10"],
    defaultLabels: "selected"
)
expectEqual(appearance.scale, 2, "scale clamp")
expectEqual(appearance.labels, "none", "bad labels")
expectEqual(appearance.deadZone, 0, "dead zone clamp")
expectEqual(appearance.restMs, 40, "legacy rest env")
expectEqual(appearance.closeGraceMs, 10, "close env")
let defaults = loadAppearance(data: nil, env: [:], defaultLabels: "selected")
expectEqual(defaults.labels, "selected", "default labels")
expectEqual(defaults.ringRadius(count: 4, satellite: false), 110, "radius")
expectEqual(Appearance(scale: 2).ringRadius(count: 4, satellite: false), 220, "scaled radius")

if failures > 0 {
    fputs("\(failures) failed\n", stderr)
    exit(1)
}
print("ok")
