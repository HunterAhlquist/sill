import Foundation
import StreamProtocol

/// One sample as macOS wants it: pressure 0…1, tilt −1…1 on each axis (x positive to the right, y
/// positive away from the user).
package struct PenPoint: Equatable, Sendable {
    package var pressure: Double
    package var tiltX: Double
    package var tiltY: Double
    /// The tip is on the glass: the pen's first button, as a tablet driver reports it.
    package var tipDown: Bool

    package init(pressure: Double, tiltX: Double = 0, tiltY: Double = 0, tipDown: Bool) {
        self.pressure = min(max(pressure, 0), 1)
        self.tiltX = min(max(tiltX, -1), 1)
        self.tiltY = min(max(tiltY, -1), 1)
        self.tipDown = tipDown
    }
}

/// An Apple Pencil's messages (kind 29, Pen.swift) as what the Mac posts for them
/// (docs/pencil-pressure-plan.md §4.1): the pen coming into range and leaving it, and each sample as
/// a move, the left button down or the button up with a tablet pen's pressure and tilt. Pure: it
/// decides, InputInjector posts (through its own pointer path, so the button's state, the click
/// count and the dry run are shared with kind 8).
///
/// What it keeps true, whatever arrives and in whatever order:
/// - every point lies between an enter and a leave;
/// - a down it posted gets exactly one up: its own, a cancel's, a leave's, the device leaving, the
///   host's end, or another device's left button coming up under it;
/// - the pen leaves before any mouse input (kind 8: a finger, a trackpad, another device) is
///   posted with the tip up, so no later click reads as a pen's, and by itself `idleLeave` seconds
///   after its last message with the tip up (an iPad whose Pencil cannot hover says nothing between
///   strokes).
package struct PenTablet: Sendable {
    /// A connection, as KeyStrokes names one.
    package typealias Device = ObjectIdentifier

    /// A position as the device sent it: a fraction of the streamed frame.
    package struct Place: Equatable, Sendable {
        package var x: Double
        package var y: Double
    }

    package enum Post: Equatable, Sendable {
        /// The pen comes into range.
        case enter
        /// The pen goes out of range.
        case leave
        /// The pointer moves: a drag while the button is down.
        case move(Place, PenPoint)
        /// The left button goes down.
        case down(Place, PenPoint)
        /// The left button comes up; without a place, where the pointer is.
        case up(Place?, PenPoint)
    }

    /// Seconds after the last pen message, with the tip up, at which the pen leaves by itself.
    package static let idleLeave = 1.0
    /// The least pressure a point carries while the tip is down: an app may read 0 as no contact.
    package static let pressureFloor = 0.01

    /// Between an enter and a leave.
    package private(set) var inProximity = false
    /// A down this posted has not had its up.
    package private(set) var tipDown = false
    /// Whose pen it is: the device of the last message taken.
    private var owner: Device?
    private var lastPenAt = 0.0

    package init() {}

    /// One pen message from `device`. `leftDown`: the Mac's left button is down now, whoever
    /// pressed it. A message that is not usable (`PenInput.checked`) posts nothing.
    package mutating func take(_ input: PenInput, from device: Device, leftDown: Bool, now: Double) -> [Post] {
        guard let input = input.checked() else { return [] }
        // While one device draws, another's pen is not this tablet's.
        if tipDown, let owner, owner != device { return [] }
        let samples = input.samples ?? []
        var posts: [Post] = []
        func enter(_ posts: inout [Post]) {
            if !inProximity { inProximity = true; posts.append(.enter) }
        }
        lastPenAt = now
        switch input.phase {
        case PenInput.hover:
            guard let sample = samples.first else { return [] }
            owner = device
            if tipDown {
                // A hover with the tip down: its up was lost. The button comes up here.
                tipDown = false
                posts.append(.up(Self.place(sample), Self.point(sample, tipDown: false)))
            } else {
                enter(&posts)
                posts.append(.move(Self.place(sample), Self.point(sample, tipDown: false)))
            }
        case PenInput.down:
            // A down while this pen's tip is down is a repeat; one while another device holds the
            // button cannot press it again.
            guard let sample = samples.first, !tipDown, !leftDown else { return [] }
            owner = device
            enter(&posts)
            tipDown = true
            posts.append(.down(Self.place(sample), Self.point(sample, tipDown: true)))
        case PenInput.move:
            owner = device
            enter(&posts)
            for sample in samples { posts.append(.move(Self.place(sample), Self.point(sample, tipDown: tipDown))) }
        case PenInput.up, PenInput.cancel:
            guard tipDown else { return [] }
            tipDown = false
            posts.append(.up(samples.first.map(Self.place), samples.first.map { Self.point($0, tipDown: false) } ?? Self.lifted))
        case PenInput.leave:
            guard owner == nil || owner == device else { return [] }   // another device's pen is still here
            posts = letGo()
        default:
            return []
        }
        return posts
    }

    /// Mouse input (kind 8) is about to be posted: a pointer event with its action, or a scroll
    /// (nil). With the tip up the pen leaves first, so the event is no pen's. With the tip down
    /// only the left button coming up changes anything: it ends this pen's stroke too.
    package mutating func mouse(_ action: PointerAction?) -> [Post] {
        if tipDown {
            guard action == .leftUp else { return [] }
            tipDown = false
        }
        guard inProximity else { return [] }
        inProximity = false
        owner = nil
        return [.leave]
    }

    /// `device` left: its pen's button comes up and the pen leaves.
    package mutating func deviceLeft(_ device: Device) -> [Post] {
        guard owner == device else { return [] }
        return letGo()
    }

    /// The host is going: the button up, the pen out of range.
    package mutating func releaseAll() -> [Post] { letGo() }

    /// Seconds until the pen leaves by itself; nil while it is out of range or its tip is down.
    package func leavesIn(now: Double) -> Double? {
        guard inProximity, !tipDown else { return nil }
        return max(0, lastPenAt + Self.idleLeave - now)
    }

    /// The pen leaves when nothing came from it for `idleLeave` seconds with the tip up.
    package mutating func idle(now: Double) -> [Post] {
        guard let wait = leavesIn(now: now), wait <= 0 else { return [] }
        return letGo()
    }

    private mutating func letGo() -> [Post] {
        var posts: [Post] = []
        if tipDown { tipDown = false; posts.append(.up(nil, Self.lifted)) }
        if inProximity { inProximity = false; posts.append(.leave) }
        owner = nil
        return posts
    }

    private static let lifted = PenPoint(pressure: 0, tipDown: false)

    private static func place(_ sample: PenSample) -> Place { Place(x: sample.x, y: sample.y) }

    /// A sample as a point: its pressure only while the tip is down (never under `pressureFloor`
    /// then; full, as a mouse's, when the device sent none), its angles as tilt.
    package static func point(_ sample: PenSample, tipDown: Bool) -> PenPoint {
        let tilt = tilt(altitude: sample.alt, azimuth: sample.az)
        return PenPoint(pressure: tipDown ? max(sample.p ?? 1, pressureFloor) : 0, tiltX: tilt.x, tiltY: tilt.y, tipDown: tipDown)
    }

    /// The Pencil's angles as macOS's tilt. With θ the lean from upright (π/2 − altitude), the tilt
    /// is θ's sine along the azimuth: x toward +x of the frame, y positive away from the user, so
    /// against the frame's y, which grows downward. Upright is 0,0; flat on the glass has length 1.
    /// Without both angles: no tilt.
    package static func tilt(altitude: Double?, azimuth: Double?) -> (x: Double, y: Double) {
        guard let altitude, let azimuth else { return (0, 0) }
        let lean = sin(.pi / 2 - min(max(altitude, 0), .pi / 2))
        return (lean * cos(azimuth) + 0, -lean * sin(azimuth) + 0)   // + 0: never −0
    }

    /// The pointer event a message amounts to, for the rules kind 8 goes through before it is
    /// posted (what closes a gesture's view, what brings a window forward): a down the left
    /// button's, an up or a cancel its release, a hover or a move a move, each at the message's last
    /// sample; nil for a leave. A cancel without a sample has no place, and none of those rules
    /// reads a release's.
    package static func pointerEvent(for input: PenInput) -> InputEvent? {
        let last = input.samples?.last
        switch input.phase {
        case PenInput.hover, PenInput.move: return last.map { .pointer(.move, x: $0.x, y: $0.y) }
        case PenInput.down: return last.map { .pointer(.leftDown, x: $0.x, y: $0.y) }
        case PenInput.up, PenInput.cancel: return .pointer(.leftUp, x: last?.x ?? 0, y: last?.y ?? 0)
        default: return nil
        }
    }

    /// Whether a message still goes when it has nowhere to land (nothing streams): an up or a
    /// cancel while the Mac's left button is down, which this then lets up where the pointer is if
    /// the pen pressed it, and a leave. A hover, a down and a move never do.
    package static func stillGoes(_ input: PenInput, leftDown: Bool) -> Bool {
        switch input.phase {
        case PenInput.up, PenInput.cancel: return leftDown
        case PenInput.leave: return true
        default: return false
        }
    }
}
