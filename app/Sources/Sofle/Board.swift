import AppKit
import SceneKit

/// The board as it sits on the desk: charcoal printed case with screw tabs, XDA caps, a controller with a
/// portrait OLED at the top inner edge of each half and a knurled knob under it. One unit is one key (19.05 mm).
final class Board {
    let scene = SCNScene()
    private let content = SCNNode()
    private var keys: [KeyPosition] = []
    private var caps: [Int: SCNMaterial] = [:]
    private var knobs: [SCNMaterial] = []    // left, right
    private var screens: [SCNMaterial] = []  // left, right
    private var images: [String: NSImage] = [:]

    private static let caseHeight: CGFloat = 0.42, capBase: CGFloat = 0.5, capHeight: CGFloat = 0.48
    private static let cream = NSColor(hex: 0xE9E4D6), grey = NSColor(hex: 0x8E8F8B), darkGrey = NSColor(hex: 0x6C6D6A)
    private static let ink = NSColor(hex: 0x33353A), shell = NSColor(hex: 0x26272A), black = NSColor(hex: 0x101012)

    /// Cap colors by position, from the real board.
    private static func capColor(_ i: Int) -> NSColor {
        switch i {
        case 0, 12, 24, 36, 11, 23, 35, 49, 50, 51, 52, 56...59: return grey  // outer columns, left modifiers, arrows
        case 53, 54, 55: return darkGrey                                     // thumbs
        default: return cream
        }
    }

    init() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal  // the board is wide: fit it to the window's width
        camera.camera?.fieldOfView = 56
        camera.position = SCNVector3(0, 18, 10.5)
        camera.look(at: SCNVector3(0, 0, 0.5))
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 700
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 4
        sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.45)
        sun.light?.orthographicScale = 12
        sun.position = SCNVector3(-5, 20, 6)
        sun.look(at: SCNVector3(0, 0, 0))
        for node in [camera, ambient, sun, content] { scene.rootNode.addChildNode(node) }
    }

    func show(keys: [KeyPosition], legends: [String], knobs knobText: [String], screens screenImages: [CGImage]) {
        if keys != self.keys { build(keys) }
        for (i, material) in caps {
            let text = i < legends.count ? legends[i] : "", tall = keys[i].h / keys[i].w
            material.diffuse.contents = cached("\(i)|\(text)") { Self.legend(text, on: Self.capColor(i), aspect: tall) }
        }
        for (material, text) in zip(knobs, knobText) { material.diffuse.contents = cached("knob|\(text)") { Self.knobTop(text) } }
        for (material, image) in zip(screens, screenImages) { material.diffuse.contents = image }
    }

    private func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let image = images[key] { return image }
        let image = make()
        images[key] = image
        return image
    }

    // MARK: Model

    private struct Placed { var x, z, angle: CGFloat, left: Bool }

    /// Center of a key in the scene. ZMK draws the halves one key apart; on a desk they sit further apart.
    private static func place(_ k: KeyPosition) -> Placed {
        let a = k.r * .pi / 180, cx = k.x + k.w / 2 - k.rx, cy = k.y + k.h / 2 - k.ry
        let x = k.rx + cx * cos(a) - cy * sin(a), y = k.ry + cx * sin(a) + cy * cos(a)
        return Placed(x: x - 7.5 + (x < 7.5 ? -1.2 : 1.2), z: y - 2.6, angle: a, left: x < 7.5)
    }

    private func build(_ keys: [KeyPosition]) {
        self.keys = keys
        caps = [:]; knobs = []; screens = []; images = [:]
        content.childNodes.forEach { $0.removeFromParentNode() }
        let placed = keys.map(Self.place), sofle = keys.count == 60
        var geometries: [String: SCNGeometry] = [:]

        for left in [true, false] {
            let side: CGFloat = left ? -1 : 1
            var outline: CGPath = CGMutablePath()
            func pad(_ w: CGFloat, _ h: CGFloat, x: CGFloat, z: CGFloat, angle: CGFloat = 0, radius: CGFloat = 0.12) {
                var t = CGAffineTransform(translationX: x, y: z).rotated(by: angle)
                outline = outline.union(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: &t))
            }

            for (i, p) in placed.enumerated() where p.left == left {
                pad(keys[i].w + 0.36, keys[i].h + 0.36, x: p.x, z: p.z, angle: p.angle)
                if sofle, Layout.encoders.contains(i) {
                    controller(at: p, left: left, pad: pad)
                    continue
                }
                let size = "\(keys[i].w)x\(keys[i].h)"
                let geometry = geometries[size] ?? Self.cap(w: keys[i].w, h: keys[i].h)
                geometries[size] = geometry
                let cap = SCNNode(geometry: geometry.copy() as? SCNGeometry)
                let material = Self.matte(Self.capColor(i))
                material.diffuse.mipFilter = .linear
                cap.geometry?.materials = [material]
                cap.position = SCNVector3(p.x, Self.capBase, p.z)
                cap.eulerAngles.y = -p.angle
                content.addChildNode(cap)
                caps[i] = material
            }

            if sofle {
                // Mounting-screw tabs: above the inner column, twice on the outer edge, and past the big thumb key.
                let thumb = placed[left ? 54 : 55]
                let tabs: [(CGFloat, CGFloat)] = [
                    (placed[left ? 5 : 6].x, placed[left ? 5 : 6].z - 0.82),
                    (placed[left ? 12 : 23].x + side * 0.82, placed[left ? 12 : 23].z),
                    (placed[left ? 36 : 49].x + side * 0.82, placed[left ? 36 : 49].z + 0.1),
                    (thumb.x - side * 0.75 * cos(thumb.angle) - 0.5 * sin(thumb.angle), thumb.z - side * 0.75 * sin(thumb.angle) + 0.5 * cos(thumb.angle)),
                ]
                for (x, z) in tabs {
                    pad(0.56, 0.56, x: x, z: z, radius: 0.28)
                    let screw = SCNCylinder(radius: 0.11, height: 0.04)
                    screw.materials = [Self.matte(NSColor(hex: 0x4A4C50))]
                    add(screw, x: x, y: Self.caseHeight + 0.02, z: z)
                }
            }

            // One solid from the union of the pads. The path is drawn in (x, z) and stood up by the node's rotation.
            var flip = CGAffineTransform(scaleX: 1, y: -1)
            let path = NSBezierPath(cgPath: outline.copy(using: &flip) ?? outline)
            path.flatness = 0.005
            let shape = SCNShape(path: path, extrusionDepth: Self.caseHeight)
            shape.chamferRadius = 0.03
            let material = Self.matte(Self.shell)
            material.diffuse.contents = Self.layerLines
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(96, 96, 1)
            shape.materials = [material]
            let shell = add(shape, x: 0, y: Self.caseHeight / 2, z: 0)
            shell.eulerAngles.x = -.pi / 2
        }
    }

    /// Controller, OLED and knob. `knob` is the encoder's position; the controller sits lengthwise above it.
    private func controller(at knob: Placed, left: Bool, pad: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) -> Void) {
        let top = Self.caseHeight, x = knob.x, z = knob.z - 2.2
        pad(1.36, 3.3, x, knob.z - 1.55, 0, 0.12)

        // Pro Micro style board with its two rows of socket pins. The right half's is mounted upside down, so it sits higher.
        let lift: CGFloat = left ? 0.1 : 0.16
        add(SCNBox(width: 0.94, height: 0.06, length: 1.74, chamferRadius: 0.01), Self.black, x: x, y: top + lift, z: z)
        for edge in [-0.4, 0.4] {
            add(SCNBox(width: 0.08, height: lift + 0.05, length: 1.6, chamferRadius: 0), NSColor(hex: 0x6E2424), x: x + edge, y: top + (lift + 0.05) / 2, z: z)
        }
        // USB-C at the top end on both halves: above the board on the left, under it on the right.
        let usb = add(SCNBox(width: 0.47, height: 0.16, length: 0.38, chamferRadius: 0.05), NSColor(hex: 0xA9ABB0), x: x, y: top + lift + (left ? 0.1 : -0.06), z: z - 0.76)
        usb.geometry?.firstMaterial?.lightingModel = .blinn

        // 128x32 OLED mounted in portrait: the stock screen is drawn landscape, so it reads turned a quarter clockwise.
        add(SCNBox(width: 0.64, height: 0.07, length: 1.84, chamferRadius: 0.02), Self.black, x: x, y: top + lift + 0.1, z: z)
        let screen = SCNMaterial()
        screen.lightingModel = .constant
        screen.diffuse.magnificationFilter = .nearest
        flat(width: 1.6, height: 0.4, screen, x: x, y: top + lift + 0.14, z: z, turned: .pi / 2)
        screens.append(screen)

        let cylinder = SCNCylinder(radius: 0.42, height: 0.72)
        cylinder.radialSegmentCount = 64
        let side = SCNMaterial()
        side.diffuse.contents = Self.knurl
        side.diffuse.wrapS = .repeat
        side.diffuse.contentsTransform = SCNMatrix4MakeScale(40, 1, 1)
        side.specular.contents = NSColor(white: 0.35, alpha: 1)
        cylinder.materials = [side, Self.matte(Self.black), Self.matte(Self.black)]
        add(cylinder, x: knob.x, y: top + 0.36, z: knob.z)
        let label = SCNMaterial()
        label.lightingModel = .constant
        label.diffuse.mipFilter = .linear
        flat(width: 0.84, height: 0.84, label, x: knob.x, y: top + 0.725, z: knob.z, turned: 0)
        knobs.append(label)
    }

    @discardableResult
    private func add(_ geometry: SCNGeometry, _ color: NSColor? = nil, x: CGFloat, y: CGFloat, z: CGFloat) -> SCNNode {
        if let color { geometry.materials = [Self.matte(color)] }
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x, y, z)
        content.addChildNode(node)
        return node
    }

    /// A plane lying face up, the top of its image pointing away from the viewer, then turned clockwise as seen from above.
    private func flat(width: CGFloat, height: CGFloat, _ material: SCNMaterial, x: CGFloat, y: CGFloat, z: CGFloat, turned: CGFloat) {
        let plane = SCNNode(geometry: SCNPlane(width: width, height: height))
        plane.geometry?.materials = [material]
        plane.eulerAngles.x = -.pi / 2
        let holder = SCNNode()
        holder.position = SCNVector3(x, y, z)
        holder.eulerAngles.y = -turned
        holder.addChildNode(plane)
        content.addChildNode(holder)
    }

    private static func matte(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        return material
    }

    /// XDA cap: every row the same low height, sides that taper only slightly, a wide shallow spherical dish on top.
    /// A stack of rounded-rectangle rings from the base up to the rim, then rings shrinking to the center of the dish.
    private static func cap(w: CGFloat, h: CGFloat) -> SCNGeometry {
        let dish: CGFloat = 0.06, m = 6, count = 4 * (m + 1)
        var points: [SCNVector3] = [], uvs: [CGPoint] = []
        func ring(inset: CGFloat, y: CGFloat, radius: CGFloat, scale: CGFloat = 1) {
            let a = w / 2 - inset - radius, b = h / 2 - inset - radius
            for corner in 0..<4 {
                for j in 0...m {
                    let t = (CGFloat(corner) + CGFloat(j) / CGFloat(m)) * .pi / 2
                    let x = ((corner == 0 || corner == 3 ? a : -a) + radius * cos(t)) * scale
                    let z = ((corner < 2 ? b : -b) + radius * sin(t)) * scale
                    points.append(SCNVector3(x, y, z))
                    uvs.append(CGPoint(x: x / w + 0.5, y: z / h + 0.5))  // the legend image is projected straight down
                }
            }
        }
        // (inset from the 1u footprint, height, corner radius)
        for (inset, y, radius) in [(0.022, 0, 0.05), (0.03, 0.06, 0.07), (0.085, 0.4, 0.12), (0.095, 0.45, 0.14), (0.11, 0.475, 0.16), (0.135, capHeight, 0.18)] as [(CGFloat, CGFloat, CGFloat)] {
            ring(inset: inset, y: y, radius: radius)
        }
        for scale in [0.8, 0.6, 0.4, 0.2] as [CGFloat] { ring(inset: 0.135, y: capHeight - dish * (1 - scale * scale), radius: 0.18, scale: scale) }
        points.append(SCNVector3(0, capHeight - dish, 0))
        uvs.append(CGPoint(x: 0.5, y: 0.5))

        var indices: [Int32] = []
        let rings = (points.count - 1) / count, center = Int32(points.count - 1)
        for r in 0..<rings {
            for j in 0..<count {
                let a = Int32(r * count + j), b = Int32(r * count + (j + 1) % count)
                indices += r < rings - 1 ? [a, a + Int32(count), b, b, a + Int32(count), b + Int32(count)] : [a, center, b]
            }
        }
        var normals = [simd_float3](repeating: .zero, count: points.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let i = [Int(indices[t]), Int(indices[t + 1]), Int(indices[t + 2])], p = i.map { simd_float3(points[$0]) }
            let n = simd_cross(p[1] - p[0], p[2] - p[0])
            for v in i { normals[v] += n }
        }
        return SCNGeometry(sources: [
            SCNGeometrySource(vertices: points),
            SCNGeometrySource(normals: normals.map { SCNVector3(simd_normalize($0)) }),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: Textures

    private static func legend(_ text: String, on color: NSColor, aspect: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256 * aspect), flipped: false) { rect in
            color.setFill()
            rect.fill()
            draw(text, in: rect, size: text.count <= 1 ? 92 : 64, fitting: 156, color: ink)
            return true
        }
    }

    private static func knobTop(_ text: String) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSColor(hex: 0x17181A).setFill()
            NSBezierPath(ovalIn: rect).fill()
            draw(text, in: rect, size: 44, fitting: 190, color: NSColor(hex: 0xD9DBE0))
            return true
        }
    }

    /// Centered text, shrunk until its widest line fits.
    private static func draw(_ text: String, in rect: NSRect, size: CGFloat, fitting width: CGFloat, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        func string(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: style])
        }
        var s = string(size)
        if s.size().width > width { s = string(size * width / s.size().width) }
        let height = s.size().height
        s.draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
    }

    private static func stripes(_ a: NSColor, _ b: NSColor, vertical: Bool) -> NSImage {
        NSImage(size: vertical ? NSSize(width: 4, height: 1) : NSSize(width: 1, height: 4), flipped: false) { rect in
            a.setFill()
            rect.fill()
            b.setFill()
            (vertical ? NSRect(x: 0, y: 0, width: 2, height: 1) : NSRect(x: 0, y: 0, width: 1, height: 2)).fill()
            return true
        }
    }
    /// The faint lines of a 3D print.
    private static let layerLines = stripes(shell, NSColor(hex: 0x292A2D), vertical: false)
    private static let knurl = stripes(NSColor(hex: 0x1B1C1E), NSColor(hex: 0x0C0C0D), vertical: true)
}
