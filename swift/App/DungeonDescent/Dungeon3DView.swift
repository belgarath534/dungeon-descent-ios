import SwiftUI
import RealityKit
import DungeonCore

/// ROOM3D_THEMES: each dungeon's walls, floor, ceiling, torchlight and fog.
struct Theme3D {
    let wall: UInt32, floor: UInt32, ceil: UInt32, torch: UInt32, fog: UInt32, ambient: UInt32

    static let all: [String: Theme3D] = [
        "Crypt of Malachar": .init(wall: 0x5a544a, floor: 0x453f36, ceil: 0x2e2822, torch: 0xff8833, fog: 0x000000, ambient: 0x3a3025),
        "The Ashbound Wastes": .init(wall: 0x4a352a, floor: 0x352520, ceil: 0x241813, torch: 0xff4411, fog: 0x1a0800, ambient: 0x3a1c10),
        "Frosthold Abyss": .init(wall: 0x5a7080, floor: 0x455a68, ceil: 0x2e3d48, torch: 0x88ccff, fog: 0x0a1520, ambient: 0x25384a),
        "The Sunken Archives": .init(wall: 0x455a52, floor: 0x30453d, ceil: 0x22322c, torch: 0x44ccaa, fog: 0x001510, ambient: 0x1a3830),
        "The Hollow": .init(wall: 0x6a655a, floor: 0x50493e, ceil: 0x38332c, torch: 0xccccdd, fog: 0x1a1a1f, ambient: 0x36363e),
        "The Whispering Forest": .init(wall: 0x4a5a3a, floor: 0x3a422a, ceil: 0x28301c, torch: 0x88cc44, fog: 0x0a1005, ambient: 0x2a3818),
        "The Infernal Descent": .init(wall: 0x5c2418, floor: 0x452012, ceil: 0x2e1208, torch: 0xff2200, fog: 0x150300, ambient: 0x431408),
        "The Abyssal Deep": .init(wall: 0x2a3450, floor: 0x1e2438, ceil: 0x161c2a, torch: 0x2299ff, fog: 0x02040a, ambient: 0x18243c),
        "The Shadow World": .init(wall: 0x342a3e, floor: 0x261f2e, ceil: 0x1c1722, torch: 0x8844cc, fog: 0x0a0510, ambient: 0x2c1c3a),
    ]

    static func of(_ dungeon: String) -> Theme3D { all[dungeon] ?? all["Crypt of Malachar"]! }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// 3D Mode's view: the floor's rooms built in RealityKit, seen from where
/// you stand. You face north like the compass; drag to look around. It's
/// for sighted play, so VoiceOver skips it (the sound does the work).
struct Dungeon3DView: UIViewRepresentable {
    let graph: RoomGraph
    let dungeon: String
    let settings: ThreeDMode.Settings

    func makeCoordinator() -> DungeonScene3D { DungeonScene3D() }

    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        context.coordinator.setup(v, dungeon: dungeon)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(DungeonScene3D.look(_:)))
        v.addGestureRecognizer(pan)
        context.coordinator.update(graph, settings: settings)
        return v
    }

    func updateUIView(_ v: ARView, context: Context) {
        context.coordinator.update(graph, settings: settings)
    }

    static func dismantleUIView(_ v: ARView, coordinator: DungeonScene3D) {
        coordinator.stop()
    }
}

@MainActor
final class DungeonScene3D: NSObject {
    // The web version's room size: 10 wide, 12 deep, 4.2 high, 2.4-wide doors.
    static let roomW: Float = 10, roomD: Float = 12, roomH: Float = 4.2, doorW: Float = 2.4, doorH: Float = 3
    static let wallT: Float = 0.3

    private weak var view: ARView?
    // Made in setup(), on the main thread with the view.
    private var root: AnchorEntity!
    private var camera: PerspectiveCamera!
    private var torch: PointLight!
    private var fill: DirectionalLight!
    private var rooms: [String: (doors: [Compass], entity: Entity)] = [:]
    private var theme = Theme3D.of("")
    private var materials: (wall: SimpleMaterial, floor: SimpleMaterial, ceil: SimpleMaterial, flame: UnlitMaterial)?
    private var yaw: Float = 0
    private var at: (Int, Int)?
    private var flicker: Timer?
    private var settings = ThreeDMode.Settings()

    func setup(_ v: ARView, dungeon: String) {
        view = v
        root = AnchorEntity(world: .zero)
        camera = PerspectiveCamera()
        torch = PointLight()
        fill = DirectionalLight()
        theme = Theme3D.of(dungeon)
        v.environment.background = .color(UIColor(hex: theme.fog))
        v.environment.lighting.intensityExponent = -2
        v.renderOptions.insert(.disableMotionBlur)
        materials = (
            wall: SimpleMaterial(color: UIColor(hex: theme.wall), roughness: 0.9, isMetallic: false),
            floor: SimpleMaterial(color: UIColor(hex: theme.floor), roughness: 0.95, isMetallic: false),
            ceil: SimpleMaterial(color: UIColor(hex: theme.ceil), roughness: 0.95, isMetallic: false),
            flame: UnlitMaterial(color: UIColor(hex: theme.torch))
        )
        camera.camera.fieldOfViewInDegrees = 70
        root.addChild(camera)
        torch.light.color = UIColor(hex: theme.torch)
        torch.light.intensity = 60000
        torch.light.attenuationRadius = 16
        root.addChild(torch)
        fill.light.color = UIColor(hex: theme.ambient)
        fill.light.intensity = 900
        fill.look(at: [0, 0, 0], from: [3, 10, 4], relativeTo: nil)
        root.addChild(fill)
        v.scene.addAnchor(root)
    }

    func stop() {
        flicker?.invalidate()
        flicker = nil
    }

    // MARK: Building rooms

    private static func center(_ gx: Int, _ gy: Int) -> SIMD3<Float> {
        [Float(gx) * roomW, 0, Float(gy) * roomD]
    }

    private func box(_ w: Float, _ h: Float, _ d: Float, _ m: RealityKit.Material, at p: SIMD3<Float>) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [m])
        e.position = p
        return e
    }

    /// One room: floor, ceiling, four walls with a gap (and a lintel) where
    /// each door is, and two torches.
    private func build(_ c: RoomGraph.Cell) -> Entity {
        guard let m = materials else { return Entity() }
        let room = Entity()
        let W = Self.roomW, D = Self.roomD, H = Self.roomH, T = Self.wallT
        room.position = Self.center(c.gx, c.gy)
        room.addChild(box(W, 0.1, D, m.floor, at: [0, -0.05, 0]))
        room.addChild(box(W, 0.1, D, m.ceil, at: [0, H + 0.05, 0]))
        for d in Compass.allCases {
            let alongX = d == .north || d == .south
            let span = alongX ? W : D
            let offset: SIMD3<Float> = [Float(d.dx) * W / 2, 0, Float(d.dy) * D / 2]
            func piece(_ length: Float, _ height: Float, _ shift: Float, _ y: Float) {
                let size: SIMD3<Float> = alongX ? [length, height, T] : [T, height, length]
                let delta: SIMD3<Float> = alongX ? [shift, y, 0] : [0, y, shift]
                room.addChild(box(size.x, size.y, size.z, m.wall, at: offset + delta))
            }
            if c.has(d) {
                let side = (span - Self.doorW) / 2
                piece(side, H, -(Self.doorW / 2 + side / 2), H / 2)
                piece(side, H, Self.doorW / 2 + side / 2, H / 2)
                piece(Self.doorW, H - Self.doorH, 0, Self.doorH + (H - Self.doorH) / 2)
            } else {
                piece(span, H, 0, H / 2)
            }
        }
        // Torches on the east and west walls.
        for x in [-W / 2 + 0.25, W / 2 - 0.25] {
            room.addChild(box(0.15, 0.35, 0.15, m.flame, at: [x, 2.4, -D / 4]))
        }
        return room
    }

    // MARK: Updating

    func update(_ g: RoomGraph, settings s: ThreeDMode.Settings) {
        guard let v = view, root != nil else { return }
        if s != settings || flicker == nil { apply(s, v) }
        // A new floor reuses grid spots with different doors: start over.
        let stale = rooms.contains { entry in
            guard let c = g.cells[entry.key] else { return true }
            return Set(c.doors) != Set(entry.value.doors)
        }
        if stale {
            rooms.values.forEach { $0.entity.removeFromParent() }
            rooms = [:]
            at = nil
        }
        for (k, c) in g.cells where rooms[k] == nil {
            let e = build(c)
            root.addChild(e)
            rooms[k] = (c.doors, e)
        }
        let here = (g.gx, g.gy)
        guard at.map({ $0 != here }) ?? true else { return }
        let first = at == nil
        at = here
        yaw = 0
        let p = Self.center(g.gx, g.gy)
        let t = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: p + [0, 1.6, 0])
        let light = Transform(scale: .one, rotation: simd_quatf(), translation: p + [0, 3.2, 0])
        if first {
            camera.transform = t
            torch.transform = light
        } else {
            camera.move(to: t, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
            torch.move(to: light, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
        }
    }

    private func apply(_ s: ThreeDMode.Settings, _ v: ARView) {
        settings = s
        if s.fpsCounter { v.debugOptions.insert(.showStatistics) } else { v.debugOptions.remove(.showStatistics) }
        fill.shadow = s.shadows ? DirectionalLightComponent.Shadow(maximumDistance: 30, depthBias: 2) : nil
        flicker?.invalidate()
        flicker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.torch.light.intensity = self.settings.torchFlicker ? Float.random(in: 50000...68000) : 60000
            }
        }
    }

    /// Drag to turn and look around the room.
    @objc func look(_ g: UIPanGestureRecognizer) {
        guard camera != nil else { return }
        let dx = Float(g.translation(in: g.view).x)
        g.setTranslation(.zero, in: g.view)
        yaw -= dx * 0.006
        camera.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}

/// A small top-down map of the rooms you've seen (sighted play only).
struct Minimap3D: View {
    let graph: RoomGraph

    var body: some View {
        Canvas { ctx, size in
            let xs = graph.cells.values.map(\.gx), ys = graph.cells.values.map(\.gy)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let cols = CGFloat(maxX - minX + 1), rows = CGFloat(maxY - minY + 1)
            let cell = min(size.width / cols, size.height / rows, 22)
            let ox = (size.width - cell * cols) / 2, oy = (size.height - cell * rows) / 2
            for c in graph.cells.values {
                let r = CGRect(x: ox + CGFloat(c.gx - minX) * cell + 2, y: oy + CGFloat(c.gy - minY) * cell + 2,
                               width: cell - 4, height: cell - 4)
                let here = c.gx == graph.gx && c.gy == graph.gy
                if here {
                    ctx.fill(Path(r), with: .color(Theme.gold))
                } else if c.visited {
                    ctx.fill(Path(r), with: .color(Color(white: 0.35)))
                } else if graph.cells.values.contains(where: { $0.visited && abs($0.gx - c.gx) + abs($0.gy - c.gy) == 1 && $0.has(c.gx > $0.gx ? .east : c.gx < $0.gx ? .west : c.gy > $0.gy ? .south : .north) }) {
                    ctx.stroke(Path(r), with: .color(Color(white: 0.3)), lineWidth: 1)
                }
            }
        }
        .frame(width: 110, height: 110)
        .background(Color.black.opacity(0.55))
        .overlay(Rectangle().stroke(Theme.borderDim))
    }
}
