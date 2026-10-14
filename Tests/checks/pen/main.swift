import Foundation

// PenTablet (Sources/SillHost/PenTablet.swift) against docs/pencil-pressure-plan.md §4.1: an Apple
// Pencil's messages (kind 29) as what the Mac posts. Compiled with StreamProtocol's sources as one
// module (build.sh).
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

typealias Post = PenTablet.Post
final class Connection {}
let ipadConnection = Connection(), phoneConnection = Connection()
let ipad = ObjectIdentifier(ipadConnection), phone = ObjectIdentifier(phoneConnection)

func sample(_ x: Double, _ y: Double, p: Double? = nil, alt: Double? = nil, az: Double? = nil) -> PenSample {
    PenSample(x: x, y: y, p: p, alt: alt, az: az)
}
func message(_ phase: String, _ samples: PenSample...) -> PenInput { PenInput(phase: phase, samples: samples.isEmpty ? nil : samples) }
func place(_ x: Double, _ y: Double) -> PenTablet.Place { PenTablet.Place(x: x, y: y) }
func hovering(_ tiltX: Double = 0, _ tiltY: Double = 0) -> PenPoint { PenPoint(pressure: 0, tiltX: tiltX, tiltY: tiltY, tipDown: false) }
func drawing(_ pressure: Double, _ tiltX: Double = 0, _ tiltY: Double = 0) -> PenPoint { PenPoint(pressure: pressure, tiltX: tiltX, tiltY: tiltY, tipDown: true) }
let lifted = PenPoint(pressure: 0, tipDown: false)
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

// MARK: A stroke

do {
    var pen = PenTablet()
    check(!pen.inProximity && !pen.tipDown, "a new tablet: out of range, the tip up")
    check(pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 0) == [.enter, .move(place(0.3, 0.5), hovering())],
          "the first hover: the pen enters, then moves without pressure")
    check(pen.inProximity && !pen.tipDown, "in range after a hover")
    check(pen.take(message(PenInput.hover, sample(0.31, 0.5)), from: ipad, leftDown: false, now: 0.01) == [.move(place(0.31, 0.5), hovering())],
          "a second hover: only the move")
    check(pen.take(message(PenInput.down, sample(0.31, 0.5, p: 0.2)), from: ipad, leftDown: false, now: 0.02) == [.down(place(0.31, 0.5), drawing(0.2))],
          "a down in range: the button down with its pressure")
    check(pen.tipDown, "the tip is down")
    check(pen.take(message(PenInput.move, sample(0.32, 0.5, p: 0.4), sample(0.33, 0.5, p: 0.6), sample(0.34, 0.5, p: 0.8)), from: ipad, leftDown: true, now: 0.03)
          == [.move(place(0.32, 0.5), drawing(0.4)), .move(place(0.33, 0.5), drawing(0.6)), .move(place(0.34, 0.5), drawing(0.8))],
          "a move: every sample, oldest first, each with its pressure")
    check(pen.take(message(PenInput.up, sample(0.34, 0.5)), from: ipad, leftDown: true, now: 0.04) == [.up(place(0.34, 0.5), lifted)],
          "an up: the button up there, without pressure")
    check(!pen.tipDown && pen.inProximity, "the tip up, the pen still in range")
    check(pen.take(message(PenInput.up, sample(0.34, 0.5)), from: ipad, leftDown: false, now: 0.05) == [], "a second up: nothing")
    check(pen.take(message(PenInput.leave), from: ipad, leftDown: false, now: 0.06) == [.leave], "a leave: the pen leaves")
    check(!pen.inProximity, "out of range")
    check(pen.take(message(PenInput.leave), from: ipad, leftDown: false, now: 0.07) == [], "a second leave: nothing")
}

// A Pencil that cannot hover: the down comes first.
do {
    var pen = PenTablet()
    check(pen.take(message(PenInput.down, sample(0.5, 0.5, p: 0.3)), from: ipad, leftDown: false, now: 0) == [.enter, .down(place(0.5, 0.5), drawing(0.3))],
          "a down out of range: the pen enters first")
    check(pen.take(message(PenInput.down, sample(0.5, 0.5, p: 0.3)), from: ipad, leftDown: true, now: 0.01) == [], "a down with the tip down: nothing")
    check(pen.take(message(PenInput.down, sample(0.5, 0.5, p: 0.3)), from: ipad, leftDown: false, now: 0.01) == [] && pen.tipDown,
          "nor when the Mac's button reads up: the pen's own down still has no up")
    check(pen.take(message(PenInput.cancel), from: ipad, leftDown: true, now: 0.02) == [.up(nil, lifted)], "a cancel without a sample: the button up where the pointer is")
    check(pen.take(message(PenInput.cancel), from: ipad, leftDown: false, now: 0.03) == [], "a cancel with the tip up: nothing")
    _ = pen.take(message(PenInput.down, sample(0.5, 0.5, p: 0.3)), from: ipad, leftDown: false, now: 0.04)
    check(pen.take(message(PenInput.cancel, sample(0.6, 0.6)), from: ipad, leftDown: true, now: 0.05) == [.up(place(0.6, 0.6), lifted)], "a cancel with a sample: the button up there")
}

// Messages out of order.
do {
    var pen = PenTablet()
    check(pen.take(message(PenInput.move, sample(0.2, 0.2, p: 0.9)), from: ipad, leftDown: false, now: 0) == [.enter, .move(place(0.2, 0.2), hovering())],
          "a move with the tip up (its down was lost): enters, and moves without pressure")
    check(pen.take(message(PenInput.up, sample(0.2, 0.2)), from: ipad, leftDown: false, now: 0.01) == [], "an up without a down: nothing")
    check(pen.take(message(PenInput.down, sample(0.2, 0.2, p: 0.5)), from: ipad, leftDown: true, now: 0.02) == [],
          "a down while another device holds the button: nothing")
    check(!pen.tipDown, "and the tip is not down")
    _ = pen.take(message(PenInput.down, sample(0.2, 0.2, p: 0.5)), from: ipad, leftDown: false, now: 0.03)
    check(pen.take(message(PenInput.hover, sample(0.4, 0.4)), from: ipad, leftDown: true, now: 0.04) == [.up(place(0.4, 0.4), hovering())],
          "a hover with the tip down (its up was lost): the button up there")
    check(!pen.tipDown && pen.inProximity, "the tip up after it, still in range")
    _ = pen.take(message(PenInput.down, sample(0.2, 0.2, p: 0.5)), from: ipad, leftDown: false, now: 0.05)
    check(pen.take(message(PenInput.leave), from: ipad, leftDown: true, now: 0.06) == [.up(nil, lifted), .leave], "a leave with the tip down: the button up, then the pen leaves")
    check(!pen.tipDown && !pen.inProximity, "nothing left of it")
}

// What is not usable posts nothing and changes nothing.
do {
    var pen = PenTablet()
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 0)
    let before = (pen.inProximity, pen.tipDown, pen.leavesIn(now: 0.5))
    var nan = sample(0.5, 0.5, p: 0.5); nan.x = .nan
    let unusable: [PenInput] = [
        PenInput(phase: "squeeze", samples: [sample(0.5, 0.5)]), PenInput(phase: PenInput.down), PenInput(phase: PenInput.down, samples: []),
        PenInput(phase: PenInput.down, samples: [sample(0.5, 0.5), sample(0.5, 0.5)]), PenInput(phase: PenInput.move),
        PenInput(phase: PenInput.move, samples: Array(repeating: sample(0.5, 0.5), count: 33)), PenInput(phase: PenInput.move, samples: [nan]),
        PenInput(phase: PenInput.cancel, samples: [sample(0.5, 0.5), sample(0.5, 0.5)]), PenInput(phase: PenInput.hover),
    ]
    for input in unusable {
        check(pen.take(input, from: ipad, leftDown: false, now: 0.4) == [], "not usable, nothing posted: \(input.phase) with \(input.samples?.count ?? 0)")
    }
    check((pen.inProximity, pen.tipDown, pen.leavesIn(now: 0.5)) == before, "and nothing changed: not even the time it leaves at")
    var wild = sample(0.5, 0.5); wild.p = 1.8
    check(pen.take(PenInput(phase: PenInput.down, samples: [wild]), from: ipad, leftDown: false, now: 0.6) == [.down(place(0.5, 0.5), drawing(1))],
          "a pressure over 1 is clamped, not refused")
}

// MARK: Mouse input

for action in [PointerAction.move, .leftDown, .leftUp, .rightDown, .rightUp, nil] {
    let name = action.map { "\($0)" } ?? "a scroll"
    var pen = PenTablet()
    check(pen.mouse(action) == [], "\(name) with no pen in range: nothing")
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 0)
    check(pen.mouse(action) == [.leave], "\(name) with the pen in range, its tip up: the pen leaves first")
    check(!pen.inProximity, "out of range after \(name)")
    check(pen.mouse(action) == [], "\(name) again: nothing")
    check(pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 1) == [.enter, .move(place(0.3, 0.5), hovering())],
          "the pen's next message after \(name) enters again")
    _ = pen.take(message(PenInput.down, sample(0.3, 0.5, p: 0.5)), from: ipad, leftDown: false, now: 1.1)
    if action == .leftUp {
        check(pen.mouse(action) == [.leave], "the left button coming up under the pen's stroke: the pen leaves (the button's up is the mouse's)")
        check(!pen.tipDown && !pen.inProximity, "and the stroke is over")
        check(pen.take(message(PenInput.up, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 1.2) == [], "the pen's own up then posts nothing")
    } else {
        check(pen.mouse(action) == [], "\(name) during the pen's stroke: nothing")
        check(pen.tipDown && pen.inProximity, "the stroke goes on through \(name)")
    }
}

// MARK: Leaving by itself

do {
    var pen = PenTablet()
    check(pen.leavesIn(now: 5) == nil && pen.idle(now: 5) == [], "out of range: nothing to wait for")
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 10)
    check(PenTablet.idleLeave == 1, "a second")
    check(pen.leavesIn(now: 10.25).map { near($0, 0.75) } == true, "0.25 s after its last message: 0.75 s to go")
    check(pen.idle(now: 10.99) == [] && pen.inProximity, "at 0.99 s: still in range")
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 10.9)
    check(pen.idle(now: 11.5) == [] && pen.leavesIn(now: 11.5).map { near($0, 0.4) } == true, "a message moves the time: 0.4 s to go at 11.5")
    check(pen.leavesIn(now: 11.9) == 0 && pen.leavesIn(now: 30) == 0, "due, and never negative")
    check(pen.idle(now: 11.9) == [.leave] && !pen.inProximity, "a second after its last message: the pen leaves")
    check(pen.idle(now: 12) == [], "once")
    _ = pen.take(message(PenInput.down, sample(0.3, 0.5, p: 0.5)), from: ipad, leftDown: false, now: 20)
    check(pen.leavesIn(now: 99) == nil && pen.idle(now: 99) == [], "with the tip down it never leaves by itself")
    check(pen.tipDown && pen.inProximity, "a stroke held for a minute is still a stroke")
    _ = pen.take(message(PenInput.up, sample(0.3, 0.5)), from: ipad, leftDown: true, now: 99)
    check(pen.idle(now: 99.5) == [] && pen.idle(now: 100) == [.leave], "a second after the up: the pen leaves (a Pencil that cannot hover)")
}

// MARK: Devices

do {
    var pen = PenTablet()
    _ = pen.take(message(PenInput.down, sample(0.3, 0.5, p: 0.5)), from: ipad, leftDown: false, now: 0)
    check(pen.take(message(PenInput.hover, sample(0.7, 0.7)), from: phone, leftDown: true, now: 0.1) == []
          && pen.take(message(PenInput.down, sample(0.7, 0.7, p: 1)), from: phone, leftDown: true, now: 0.1) == []
          && pen.take(message(PenInput.up, sample(0.7, 0.7)), from: phone, leftDown: true, now: 0.1) == []
          && pen.take(message(PenInput.leave), from: phone, leftDown: true, now: 0.1) == [],
          "while one device draws, another's pen posts nothing")
    check(pen.tipDown && pen.inProximity, "and the stroke goes on")
    check(pen.deviceLeft(phone) == [], "the other device leaving changes nothing")
    check(pen.deviceLeft(ipad) == [.up(nil, lifted), .leave], "the drawing device leaving: the button up where the pointer is, the pen out of range")
    check(!pen.tipDown && !pen.inProximity && pen.deviceLeft(ipad) == [], "once")
}
do {
    var pen = PenTablet()
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 0)
    check(pen.take(message(PenInput.leave), from: phone, leftDown: false, now: 0.1) == [] && pen.inProximity, "another device's leave is not this pen's")
    check(pen.take(message(PenInput.hover, sample(0.6, 0.6)), from: phone, leftDown: false, now: 0.2) == [.move(place(0.6, 0.6), hovering())],
          "with the tip up another device's pen takes over, already in range")
    check(pen.deviceLeft(ipad) == [] && pen.inProximity, "the first device leaving then changes nothing")
    check(pen.deviceLeft(phone) == [.leave], "the second leaving: the pen leaves")
}
do {
    var pen = PenTablet()
    check(pen.releaseAll() == [], "the host's end with no pen: nothing")
    _ = pen.take(message(PenInput.hover, sample(0.3, 0.5)), from: ipad, leftDown: false, now: 0)
    check(pen.releaseAll() == [.leave], "the host's end with a pen in range: it leaves")
    _ = pen.take(message(PenInput.down, sample(0.3, 0.5, p: 0.5)), from: ipad, leftDown: false, now: 1)
    check(pen.releaseAll() == [.up(nil, lifted), .leave] && pen.releaseAll() == [], "the host's end mid-stroke: the button up, the pen out of range, once")
}

// MARK: Pressure and tilt

check(PenTablet.pressureFloor == 0.01, "the floor")
check(PenTablet.point(sample(0, 0, p: 0), tipDown: true).pressure == 0.01, "no pressure with the tip down: the floor")
check(PenTablet.point(sample(0, 0, p: 0.005), tipDown: true).pressure == 0.01, "under the floor: the floor")
check(PenTablet.point(sample(0, 0, p: 0.37), tipDown: true).pressure == 0.37, "a pressure as it is")
check(PenTablet.point(sample(0, 0), tipDown: true).pressure == 1, "none sent with the tip down: full, as a mouse's")
check(PenTablet.point(sample(0, 0, p: 0.9), tipDown: false).pressure == 0, "none with the tip up, whatever was sent")
check(PenTablet.point(sample(0, 0, p: 0.5), tipDown: true).tipDown && !PenTablet.point(sample(0, 0, p: 0.5), tipDown: false).tipDown, "the tip as given")
check(PenPoint(pressure: 3, tiltX: -4, tiltY: 9, tipDown: true) == PenPoint(pressure: 1, tiltX: -1, tiltY: 1, tipDown: true), "a point clamps: pressure 0…1, tilt −1…1")
check(PenPoint(pressure: -1, tipDown: false).pressure == 0, "and never under 0")

func tilt(_ altitude: Double?, _ azimuth: Double?) -> (x: Double, y: Double) { PenTablet.tilt(altitude: altitude, azimuth: azimuth) }
func isTilt(_ got: (x: Double, y: Double), _ x: Double, _ y: Double) -> Bool { near(got.x, x) && near(got.y, y) }
check(isTilt(tilt(.pi / 2, 0), 0, 0) && isTilt(tilt(.pi / 2, 2.2), 0, 0), "upright: no tilt, whatever the azimuth")
check(isTilt(tilt(0, 0), 1, 0), "flat, its top along +x: fully right")
check(isTilt(tilt(0, .pi), -1, 0), "flat, its top along −x: fully left")
check(isTilt(tilt(0, .pi / 2), 0, -1), "flat, its top down the frame: fully toward the user (−y)")
check(isTilt(tilt(0, -.pi / 2), 0, 1), "flat, its top up the frame: fully away (+y)")
check(isTilt(tilt(.pi / 4, 0), sin(.pi / 4), 0), "leaning 45° right: sin 45°")
check(isTilt(tilt(.pi / 3, .pi / 4), 0.5 * cos(.pi / 4), -0.5 * sin(.pi / 4)), "leaning 30° down and right: half, along the azimuth")
check(isTilt(tilt(nil, 1), 0, 0) && isTilt(tilt(1, nil), 0, 0) && isTilt(tilt(nil, nil), 0, 0), "without both angles: no tilt")
check(isTilt(tilt(-0.4, 0), 1, 0) && isTilt(tilt(2.5, 0), 0, 0), "an altitude out of range is clamped: flat, upright")
check(tilt(.pi / 2, 0).x.sign == .plus && tilt(.pi / 2, 0).y.sign == .plus, "never −0")
do {
    let point = PenTablet.point(sample(0, 0, p: 0.5, alt: 0, az: .pi / 2), tipDown: true)
    check(abs(point.tiltX) < 1e-4 && abs(point.tiltY + 1) < 1e-4, "a sample's angles reach its point (as the wire rounds them, to 4 places)")
    var pen = PenTablet()
    let posts = pen.take(message(PenInput.hover, sample(0.5, 0.5, alt: .pi / 4, az: 0)), from: ipad, leftDown: false, now: 0)
    check(posts == [.enter, .move(place(0.5, 0.5), hovering(PenTablet.tilt(altitude: PenSample(x: 0, y: 0, alt: .pi / 4).alt, azimuth: 0).x, 0))],
          "a hover carries its tilt, and no pressure")
}

// MARK: For kind 8's rules, and with nowhere to land

check(PenTablet.pointerEvent(for: message(PenInput.hover, sample(0.3, 0.4))) == .pointer(.move, x: 0.3, y: 0.4), "a hover amounts to a move")
check(PenTablet.pointerEvent(for: message(PenInput.move, sample(0.1, 0.1), sample(0.3, 0.4))) == .pointer(.move, x: 0.3, y: 0.4), "a move to a move, at its last sample")
check(PenTablet.pointerEvent(for: message(PenInput.down, sample(0.3, 0.4))) == .pointer(.leftDown, x: 0.3, y: 0.4), "a down to the left button's")
check(PenTablet.pointerEvent(for: message(PenInput.up, sample(0.3, 0.4))) == .pointer(.leftUp, x: 0.3, y: 0.4), "an up to its release")
check(PenTablet.pointerEvent(for: message(PenInput.cancel, sample(0.3, 0.4))) == .pointer(.leftUp, x: 0.3, y: 0.4), "a cancel to its release")
check(PenTablet.pointerEvent(for: message(PenInput.cancel)) == .pointer(.leftUp, x: 0, y: 0), "a cancel without a sample too")
check(PenTablet.pointerEvent(for: message(PenInput.leave)) == nil && PenTablet.pointerEvent(for: message("squeeze")) == nil, "a leave and an unknown phase to nothing")
check(PenTablet.pointerEvent(for: PenInput(phase: PenInput.down)) == nil, "a down without a sample to nothing")
for (phase, down, up) in [(PenInput.hover, false, false), (PenInput.down, false, false), (PenInput.move, false, false),
                          (PenInput.up, true, false), (PenInput.cancel, true, false), (PenInput.leave, true, true), ("squeeze", false, false)] {
    check(PenTablet.stillGoes(message(phase, sample(0.5, 0.5)), leftDown: true) == down, "nowhere to land, the button down: \(phase) \(down ? "goes" : "is dropped")")
    check(PenTablet.stillGoes(message(phase, sample(0.5, 0.5)), leftDown: false) == up, "nowhere to land, the button up: \(phase) \(up ? "goes" : "is dropped")")
}

// MARK: The device (PenStrokes)

check(PenStrokes.leaveDelay == 0.1 && PenStrokes.palmLinger == 0.5, "a tenth of a second before a leave; half a second of quiet after the tip lifts")
for (on, connected, host, generation, want) in [(true, true, 1 as Int?, 1, true), (true, true, 2, 1, true), (false, true, 1, 1, false),
                                               (true, false, 1, 1, false), (true, true, nil, 1, false), (true, true, 0, 1, false), (true, true, 1, 2, false)] {
    check(PenStrokes.penMode(switchOn: on, connected: connected, hostPencil: host, generation: generation) == want,
          "as a pen: switch \(on), connected \(connected), the Mac says \(host.map(String.init) ?? "nothing"), this build's \(generation): \(want)")
}
check(PenStrokes.pressure(force: 0, maximum: 4.1667) == 0 && PenStrokes.pressure(force: 4.1667, maximum: 4.1667) == 1, "no force 0, all of it 1")
check(near(PenStrokes.pressure(force: 1.25, maximum: 5), 0.25), "a quarter of the most it reports: 0.25")
check(PenStrokes.pressure(force: 9, maximum: 4) == 1 && PenStrokes.pressure(force: -1, maximum: 4) == 0, "clamped to 0…1")
check(PenStrokes.pressure(force: 1, maximum: 0) == 0 && PenStrokes.pressure(force: .nan, maximum: 4) == 0 && PenStrokes.pressure(force: 1, maximum: .infinity) == 0,
      "no maximum, or a force that is no number: no pressure")

func reading(_ x: Double, _ y: Double, p: Double? = nil, alt: Double? = nil, az: Double? = nil, at time: Double) -> PenStrokes.Reading {
    PenStrokes.Reading(x: x, y: y, pressure: p, altitude: alt, azimuth: az, time: time)
}
check(PenStrokes.message(PenInput.down, reading(0.123456, 0.5, p: 0.31, alt: 1.0, az: 0.5, at: 77.25)) == PenInput(phase: "down", samples: [PenSample(x: 0.12346, y: 0.5, p: 0.31, alt: 1, az: 0.5)]),
      "a down: one sample, rounded as the wire carries it, no time")
check(PenStrokes.message(PenInput.hover, reading(0.2, 0.3, alt: 0.9, az: -1, at: 5)).samples?.first?.p == nil, "a hover carries no pressure")
check(PenStrokes.message(PenInput.up, reading(0.2, 0.3, at: 5)).checked() != nil && PenStrokes.message(PenInput.cancel, reading(0.2, 0.3, at: 5)).checked() != nil,
      "an up and a cancel are messages a Mac takes")
check(PenStrokes.moves([]) == [], "no readings: no message")
do {
    let frame = 1.0 / 240
    let three = PenStrokes.moves([reading(0.1, 0.5, p: 0.2, at: 10), reading(0.2, 0.5, p: 0.3, at: 10 + frame), reading(0.3, 0.5, p: 0.4, at: 10 + 2 * frame)])
    check(three == [PenInput(phase: "move", samples: [PenSample(x: 0.1, y: 0.5, p: 0.2, t: 8.3), PenSample(x: 0.2, y: 0.5, p: 0.3, t: 4.2), PenSample(x: 0.3, y: 0.5, p: 0.4)])],
          "a callback's three readings: one move, oldest first, each its milliseconds before the last, the last none")
    let many = (0..<70).map { reading(Double($0) / 100, 0.5, p: 0.5, at: 20 + Double($0) * frame) }
    let messages = PenStrokes.moves(many)
    check(messages.map { $0.samples?.count ?? 0 } == [32, 32, 6], "70 readings after a stall: 32, 32 and 6")
    check(messages.allSatisfy { $0.phase == PenInput.move && $0.checked() != nil }, "each a move a Mac takes")
    check(messages.flatMap { $0.samples ?? [] }.map(\.x) == many.map { PenSample(x: $0.x, y: 0).x }, "every reading sent, in order")
    check(messages.allSatisfy { $0.samples?.last?.t == nil && ($0.samples?.first?.t ?? 0) > 0 }, "each message's times count from its own last sample")
    check(messages[0].samples?.first?.t == 129.2 && messages[2].samples?.first?.t == 20.8, "31 and 5 readings before the last: 129.2 and 20.8 ms")
    check(PenStrokes.moves(Array(many.prefix(32))).count == 1 && PenStrokes.moves(Array(many.prefix(33))).count == 2, "32 fit one message, 33 take two")
}

// A stroke's mode is fixed as the tip lands.
do {
    var strokes = PenStrokes()
    check(strokes.stroke == nil && !strokes.hovering && !strokes.told && !strokes.canHover, "a new one: nothing")
    check(strokes.touchEnded(now: 1) == nil, "an end without a stroke: none")
    check(strokes.touchBegan(penMode: true) == .pen && strokes.stroke == .pen && strokes.told, "the tip lands in pen mode: a pen's stroke, and the Mac is told")
    check(strokes.touchEnded(now: 2) == .pen && strokes.stroke == nil, "its end goes as a pen's")
    var mouse = PenStrokes()
    check(mouse.touchBegan(penMode: false) == .mouse && mouse.stroke == .mouse && !mouse.told, "the tip lands in mouse mode: the mouse's, and the Mac is told of no pen")
    check(mouse.hover(isPencil: true, penMode: true) == .ignore, "a hover during a stroke is not sent")
    check(mouse.touchEnded(now: 2) == .mouse, "its end goes as the mouse's")
}

// The leave.
do {
    var strokes = PenStrokes()
    check(strokes.hover(isPencil: true, penMode: true) == .pen && strokes.hovering && strokes.canHover && strokes.told, "a hover in pen mode goes as a pen's")
    strokes.hoverEnded(now: 10)
    check(!strokes.leaveDue(now: 10.05), "0.05 s after the hover ended: not yet")
    check(strokes.leaveDue(now: 10.1) && !strokes.told, "0.1 s after, neither touching nor hovering: the Pencil left")
    check(!strokes.leaveDue(now: 10.2), "once")
    // A hover that ends because the tip landed.
    _ = strokes.hover(isPencil: true, penMode: true)
    strokes.hoverEnded(now: 20)
    _ = strokes.touchBegan(penMode: true)
    check(!strokes.leaveDue(now: 20.11), "the hover ended as the tip landed: no leave")
    _ = strokes.touchEnded(now: 21)
    _ = strokes.hover(isPencil: true, penMode: true)
    check(!strokes.leaveDue(now: 21.11), "the tip lifted and the hover began again: no leave")
    strokes.hoverEnded(now: 22)
    check(strokes.leaveDue(now: 22.11), "then the Pencil leaves: one leave")
    // The tip lifts straight out of range.
    _ = strokes.hover(isPencil: true, penMode: true); strokes.hoverEnded(now: 30); _ = strokes.touchBegan(penMode: true); _ = strokes.touchEnded(now: 31)
    check(!strokes.leaveDue(now: 31.05) && strokes.leaveDue(now: 31.1), "a Pencil that can hover, lifted straight out of range: a leave 0.1 s after the lift")
}
do {
    var strokes = PenStrokes()   // a Pencil that cannot hover
    _ = strokes.touchBegan(penMode: true)
    _ = strokes.touchEnded(now: 10)
    check(!strokes.leaveDue(now: 10.2) && strokes.told, "a Pencil that cannot hover sends no leave between strokes (the Mac lets its pen go by itself)")
    check(strokes.gone() && !strokes.told, "the surface going away: the Mac hears it left")
    check(!strokes.gone(), "once")
    var mouse = PenStrokes()
    check(mouse.hover(isPencil: true, penMode: false) == .mouse && mouse.canHover && !mouse.told, "a hover in mouse mode goes as the mouse's")
    mouse.hoverEnded(now: 5)
    check(!mouse.leaveDue(now: 5.2) && !mouse.gone(), "and no leave follows: the Mac was told of no pen")
    check(mouse.hover(isPencil: true, penMode: true) == .pen && mouse.told, "the switch turned on mid-hover: the next hover goes as a pen's")
}

// The stale hover as the tip lifts (an iPad Pro M4, iPadOS 27.0.1): one hover update while the tip is
// still down, carrying where the Pencil hovered before it landed. Sent as a move with the button
// down, it drew a line from the stroke's end back to its start, in both modes.
for penMode in [true, false] {
    var strokes = PenStrokes()
    _ = strokes.hover(isPencil: true, penMode: penMode)
    strokes.hoverEnded(now: 10)
    _ = strokes.touchBegan(penMode: penMode)
    check(strokes.hover(isPencil: true, penMode: penMode) == .ignore, "\(penMode ? "pen" : "mouse") mode: a Pencil hover while the tip is down goes nowhere")
    check(strokes.hover(isPencil: false, penMode: penMode) == .ignore, "\(penMode ? "pen" : "mouse") mode: nor one that does not look like the Pencil's")
    check(!strokes.hovering, "and it does not count as hovering")
    _ = strokes.touchEnded(now: 11)
    check(strokes.hover(isPencil: true, penMode: penMode) == (penMode ? .pen : .mouse), "after the touch, hovers go again")
}
do {
    var strokes = PenStrokes()
    _ = strokes.hover(isPencil: true, penMode: true)
    strokes.hoverEnded(now: 10)
    _ = strokes.touchBegan(penMode: true)
    _ = strokes.hover(isPencil: true, penMode: true)                // the stale one
    _ = strokes.touchEnded(now: 11)                                  // lifted straight out of range: no hover after
    check(strokes.leaveDue(now: 11.1), "a stale hover during the touch does not keep the Pencil hovering: the leave still comes")
    var fresh = PenStrokes()
    check(fresh.hover(isPencil: false, penMode: true) == .mouse && !fresh.hovering && !fresh.canHover,
          "the iPad's own pointer hovering: a pointer move, and no Pencil hovering")
}

// A resting palm.
do {
    var palm = PenStrokes.Palm()
    check(!palm.silent(strokeBeganAt: 5), "no Pencil yet: fingers speak")
    palm.pencil(touching: true, at: 20)
    check(palm.silent(strokeBeganAt: 10) && palm.silent(strokeBeganAt: 20.5) && palm.silent(strokeBeganAt: 0), "the tip on the glass: every finger stroke says nothing")
    check(palm.silent(strokeBeganAt: 30), "also one that begins long into the Pencil's stroke")
    palm.pencil(touching: false, at: 25)
    check(palm.silent(strokeBeganAt: 10), "a finger stroke from before the tip lifted stays silent to its end")
    check(palm.silent(strokeBeganAt: 25.4) && palm.silent(strokeBeganAt: 25.5), "one that begins within half a second of the lift: silent")
    check(!palm.silent(strokeBeganAt: 25.51) && !palm.silent(strokeBeganAt: 40), "one that begins later speaks")
    palm.pencil(touching: true, at: 41)
    check(palm.silent(strokeBeganAt: 40), "the tip lands again during it: silent")
    palm.pencil(touching: false, at: 42)
    check(palm.silent(strokeBeganAt: 40) && !palm.silent(strokeBeganAt: 43), "and to its end; the next one speaks")
}

// A Pencil's session through both ends: what the device sends, as the Mac posts it.
do {
    var device = PenStrokes()
    var mac = PenTablet()
    var posts: [Post] = []
    var leftDown = false
    func send(_ input: PenInput, at now: Double) {
        guard let taken = Wire.decode(PenInput.self, from: Wire.encode(input)) else { check(false, "\(input.phase) does not survive the wire"); return }
        for post in mac.take(taken, from: ipad, leftDown: leftDown, now: now) {
            if case .down = post { leftDown = true }
            if case .up = post { leftDown = false }
            posts.append(post)
        }
    }
    if device.hover(isPencil: true, penMode: true) == .pen { send(PenStrokes.message(PenInput.hover, reading(0.3, 0.5, alt: .pi / 4, az: 0, at: 1)), at: 1) }
    device.hoverEnded(now: 1.2)
    if device.touchBegan(penMode: true) == .pen { send(PenStrokes.message(PenInput.down, reading(0.3, 0.5, p: 0.2, alt: .pi / 2, az: 0, at: 1.2)), at: 1.2) }
    check(!device.leaveDue(now: 1.31), "no leave as the tip lands")
    for message in PenStrokes.moves([reading(0.32, 0.5, p: 0.4, alt: .pi / 2, az: 0, at: 1.21), reading(0.34, 0.5, p: 0.6, alt: .pi / 2, az: 0, at: 1.214)]) { send(message, at: 1.214) }
    // The stale hover as the tip lifts, at where the Pencil hovered before it landed: nothing goes.
    check(device.hover(isPencil: true, penMode: true) == .ignore, "the stale hover as the tip lifts is not sent")
    if device.touchEnded(now: 1.4) == .pen { send(PenStrokes.message(PenInput.up, reading(0.34, 0.5, at: 1.4)), at: 1.4) }
    if device.leaveDue(now: 1.5) { send(PenInput(phase: PenInput.leave), at: 1.5) }
    let tilt = PenTablet.tilt(altitude: PenSample(x: 0, y: 0, alt: .pi / 4).alt, azimuth: 0)
    check(posts == [.enter, .move(place(0.3, 0.5), hovering(tilt.x, tilt.y)), .down(place(0.3, 0.5), drawing(0.2)),
                    .move(place(0.32, 0.5), drawing(0.4)), .move(place(0.34, 0.5), drawing(0.6)), .up(place(0.34, 0.5), lifted), .leave],
          "a hover, a stroke and the Pencil leaving, end to end: \(posts)")
    check(!mac.inProximity && !mac.tipDown && !device.told, "both ends agree nothing is left")
}

// MARK: Random sessions against a model

/// SplitMix64: the same sessions every run.
struct Random {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func unit() -> Double { Double(next() % 10_001) / 10_000 }
}

/// What the Mac would hold after the posts so far, as InputInjector keeps it: the left button, and
/// whether the pen is in range. `penHolds`: the button is down by a pen's down.
struct Mac {
    var leftDown = false, penHolds = false, inRange = false
    var problems: [String] = []
    var enters = 0, leaves = 0, penDowns = 0, penUps = 0, strokesEndedByMouse = 0

    /// `before`: the mouse input these posts come ahead of, if any. The left button coming up under
    /// the pen's stroke is the one time the pen leaves with its button down: the up that follows is
    /// the mouse's.
    mutating func post(_ posts: [Post], before: PointerAction?? = nil) {
        for item in posts {
            switch item {
            case .enter:
                if inRange { problems.append("an enter while in range") }
                inRange = true; enters += 1
            case .leave:
                if !inRange { problems.append("a leave while out of range") }
                if penHolds, before != .some(.leftUp) { problems.append("a leave with the pen's button down") }
                inRange = false; leaves += 1
            case .move(_, let point):
                if !inRange { problems.append("a point out of range") }
                if point.tipDown != penHolds { problems.append("a move's tip \(point.tipDown) with the pen's button \(penHolds)") }
                if point.tipDown, point.pressure < PenTablet.pressureFloor { problems.append("a drag under the floor") }
                if !point.tipDown, point.pressure != 0 { problems.append("pressure with the tip up") }
            case .down(_, let point):
                if !inRange { problems.append("a down out of range") }
                if leftDown { problems.append("a down with the button down") }
                if !point.tipDown || point.pressure < PenTablet.pressureFloor { problems.append("a down without its tip or pressure") }
                leftDown = true; penHolds = true; penDowns += 1
            case .up(_, let point):
                if !inRange { problems.append("an up out of range") }
                if !penHolds { problems.append("an up the pen did not press") }
                if point.tipDown || point.pressure != 0 { problems.append("an up with its tip or pressure") }
                leftDown = false; penHolds = false; penUps += 1
            }
        }
    }

    /// Kind 8 from any device, after the tablet was told of it.
    mutating func mouse(_ action: PointerAction?) {
        if inRange, !penHolds { problems.append("mouse input with the pen in range, its tip up") }
        switch action {
        case .leftDown: leftDown = true
        case .leftUp:
            if penHolds { strokesEndedByMouse += 1 }
            leftDown = false; penHolds = false
        default: break
        }
    }
}

var random = Random(state: 0x51_11)
var sessions = 0, sessionProblems = 0, posted = 0
let phases = PenInput.phases + ["squeeze"]
let actions: [PointerAction?] = [.move, .leftDown, .leftUp, .rightDown, .rightUp, nil]
for _ in 0..<5_000 {
    var pen = PenTablet()
    var mac = Mac()
    var now = 0.0
    var gone: Set<ObjectIdentifier> = []
    for _ in 0..<80 {
        now += [0.004, 0.004, 0.02, 0.3, 1.2][random.below(5)]
        mac.post(pen.idle(now: now))                      // the injector's wait, whenever it is due
        let device = random.below(4) == 0 ? phone : ipad
        switch random.below(10) {
        case 0...6:
            guard !gone.contains(device) else { continue }
            let phase = phases[random.below(phases.count)]
            let count = [0, 1, 1, 1, 2, 3, 33][random.below(7)]
            let samples = (0..<count).map { _ in sample(random.unit(), random.unit(), p: random.below(5) == 0 ? nil : random.unit() * 1.2,
                                                         alt: random.below(3) == 0 ? nil : random.unit() * 1.6, az: random.unit() * 6.3 - 3.1) }
            let posts = pen.take(PenInput(phase: phase, samples: samples.isEmpty ? nil : samples), from: device, leftDown: mac.leftDown, now: now)
            mac.post(posts); posted += posts.count
        case 7, 8:
            let action = actions[random.below(actions.count)]
            let posts = pen.mouse(action)
            mac.post(posts, before: .some(action)); posted += posts.count
            mac.mouse(action)
        default:
            let posts = pen.deviceLeft(device)
            mac.post(posts); posted += posts.count
            gone.insert(device)
        }
        if pen.inProximity != mac.inRange || pen.tipDown != mac.penHolds {
            mac.problems.append("the tablet says in range \(pen.inProximity), tip \(pen.tipDown); the Mac has \(mac.inRange), \(mac.penHolds)")
        }
        if !mac.problems.isEmpty { break }
    }
    mac.post(pen.releaseAll())
    if mac.inRange || mac.penHolds { mac.problems.append("the host's end left the pen in range or its button down") }
    if mac.penDowns != mac.penUps + mac.strokesEndedByMouse { mac.problems.append("\(mac.penDowns) downs, \(mac.penUps) ups and \(mac.strokesEndedByMouse) ended by the mouse") }
    if mac.enters != mac.leaves { mac.problems.append("\(mac.enters) enters, \(mac.leaves) leaves") }
    sessions += 1
    if !mac.problems.isEmpty {
        sessionProblems += 1
        if sessionProblems <= 3 { print("FAIL: session \(sessions): \(mac.problems[0])") }
    }
}
check(sessionProblems == 0, "\(sessionProblems) of \(sessions) random sessions broke an invariant")
check(posted > 20_000, "the sessions posted enough to mean something: \(posted)")

print(failures == 0 ? "ok: \(checks) checks, \(sessions) random sessions" : "\(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
