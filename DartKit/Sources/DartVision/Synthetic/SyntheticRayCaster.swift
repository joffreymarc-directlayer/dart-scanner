import Foundation
import simd
import DartCore

/// A half-open rectangle of pixels: columns `x0 ..< x1`, rows `y0 ..< y1`.
struct SyntheticPixelBox: Hashable, Sendable {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int

    var isEmpty: Bool { x0 >= x1 || y0 >= y1 }

    func union(_ other: SyntheticPixelBox) -> SyntheticPixelBox {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return SyntheticPixelBox(x0: min(x0, other.x0), y0: min(y0, other.y0), x1: max(x1, other.x1), y1: max(y1, other.y1))
    }

    func expanded(by margin: Int, within width: Int, _ height: Int) -> SyntheticPixelBox {
        if isEmpty { return self }
        return SyntheticPixelBox(x0: max(0, x0 - margin), y0: max(0, y0 - margin),
                                 x1: min(width, x1 + margin), y1: min(height, y1 + margin))
    }
}

/// A rendered scene before the nuisances that change from frame to frame (shift, gain, noise).
struct SyntheticBaseImage: Sendable {
    var image: RGBImage
    /// Everything outside this box is plain wall.
    var content: SyntheticPixelBox
}

/// The analytic ray caster of VISION.md §10.1 for one scene and one camera. Internal to DartVision.
///
/// Every sample is one ray from the camera centre. It sees the nearest of: a dart or the hand, a wire of the
/// plane `z = wireHeight` (a raised wire hides the foot of a dart behind it), and the board plane `z = 0`, whose
/// colour is darkened when the segment to the lamp touches a dart.
///
/// Most pixels are far from any edge. The image is therefore rendered in blocks of 16 pixels: when the centre
/// ray of a block is further from every edge (of a wire, a surface, a dart, a shadow, the hand) than the block
/// reaches on the board, the whole block takes the colour of that ray; otherwise the block is split in four, down
/// to single pixels, which are sampled in full. The bound is conservative, so the result is exactly the image
/// that sampling every pixel would give. Rows are rendered in concurrent bands.
struct SyntheticRayCaster: Sendable {
    /// Height of the hand above the board, mm.
    static let handHeight: Double = 60
    /// Colour of the hand.
    static let handColour: SIMD3<UInt8> = SIMD3(210, 160, 130)
    /// Tint of a shadow, multiplied with `shadowStrength`: slightly cooler than the lit surface.
    static let shadowTint: SIMD3<Double> = SIMD3(0.97, 1.0, 1.04)
    /// Side of the largest block, pixels (a power of two).
    static let blockSide = 16

    // Camera.
    private let cx: Double, cy: Double, cz: Double
    private let rightX: Double, rightY: Double, rightZ: Double
    private let downX: Double, downY: Double, downZ: Double
    private let forwardX: Double, forwardY: Double, forwardZ: Double
    private let focalX: Double, focalY: Double, principalX: Double, principalY: Double
    private let width: Int, height: Int
    private let camera: SyntheticCamera

    // Scene.
    private let board: SyntheticBoard
    /// Height of the wire plane, 0 when the wires lie in the board plane.
    private let wireHeight: Double
    private let solids: [SyntheticDartSolid]
    /// Footprints of the darts on the board plane as seen from the camera (bodies, then flights).
    private let viewBody: [SyntheticFootprint]
    private let viewFlight: [SyntheticFootprint]
    /// Footprints of the shadows on the board plane and on the wire plane.
    private let shadowBody: [SyntheticFootprint]
    private let shadowFlight: [SyntheticFootprint]
    private let wireShadowBody: [SyntheticFootprint]
    private let wireShadowFlight: [SyntheticFootprint]
    private let hasLight: Bool
    private let lightX: Double, lightY: Double, lightZ: Double
    private let hasHand: Bool
    private let handX: Double, handY: Double, handRadius2: Double
    /// The hand disc as it appears on the board plane from the camera centre: a larger disc.
    private let handViewX: Double, handViewY: Double, handViewRadius: Double
    private let handColour: UInt32
    /// Packed colours of the seven paints, lit and in shadow.
    private let palette: [UInt32]
    private let shadowPalette: [UInt32]

    init(scene: SyntheticScene, camera: SyntheticCamera, solids customSolids: [SyntheticDartSolid]? = nil) {
        self.camera = camera
        cx = camera.position.x; cy = camera.position.y; cz = camera.position.z
        let rows = camera.rotationRows
        rightX = rows.right.x; rightY = rows.right.y; rightZ = rows.right.z
        downX = rows.down.x; downY = rows.down.y; downZ = rows.down.z
        forwardX = rows.forward.x; forwardY = rows.forward.y; forwardZ = rows.forward.z
        focalX = camera.intrinsics.fx; focalY = camera.intrinsics.fy
        principalX = camera.intrinsics.cx; principalY = camera.intrinsics.cy
        width = max(0, camera.imageSize.width); height = max(0, camera.imageSize.height)

        board = SyntheticBoard(radii: scene.radii)
        let raised = scene.wireHeight.isFinite && scene.wireHeight > 0 && scene.wireHeight < camera.position.z
        wireHeight = raised ? scene.wireHeight : 0
        let allSolids = customSolids ?? scene.darts.map { $0.solid() }
        solids = allSolids

        let shape = SyntheticDart.Shape.self
        let flightRadius = (shape.flightHalfWidth * shape.flightHalfWidth
            + shape.flightHalfThickness * shape.flightHalfThickness).squareRoot()
        func footprints(source: SIMD3<Double>, plane: Double) -> (body: [SyntheticFootprint], flight: [SyntheticFootprint]) {
            var bodies: [SyntheticFootprint] = [], flights: [SyntheticFootprint] = []
            for solid in allSolids {
                bodies.append(.project(from: solid.axisPoint(shape.pointStart), to: solid.axisPoint(shape.shaftEnd),
                                       radius: shape.barrelRadius, source: source, plane: plane))
                flights.append(.project(from: solid.axisPoint(shape.flightStart), to: solid.axisPoint(shape.flightEnd),
                                        radius: flightRadius, source: source, plane: plane))
            }
            return (bodies, flights)
        }
        let view = footprints(source: camera.position, plane: 0)
        viewBody = view.body
        viewFlight = view.flight

        let strength = scene.shadowStrength.isFinite ? min(1, max(0, scene.shadowStrength)) : 1
        if let light = scene.light, strength < 1, !allSolids.isEmpty,
           light.x.isFinite, light.y.isFinite, light.z.isFinite, light.z > 0 {
            hasLight = true
            lightX = light.x; lightY = light.y; lightZ = light.z
            let onBoard = footprints(source: light, plane: 0)
            shadowBody = onBoard.body
            shadowFlight = onBoard.flight
            let onWires = footprints(source: light, plane: raised ? scene.wireHeight : 0)
            wireShadowBody = onWires.body
            wireShadowFlight = onWires.flight
        } else {
            hasLight = false
            lightX = 0; lightY = 0; lightZ = 0
            shadowBody = []; shadowFlight = []; wireShadowBody = []; wireShadowFlight = []
        }

        if let hand = scene.hand, hand.radius.isFinite, hand.radius > 0, hand.centre.x.isFinite, hand.centre.y.isFinite,
           camera.position.z > SyntheticRayCaster.handHeight {
            hasHand = true
            handX = hand.centre.x; handY = hand.centre.y; handRadius2 = hand.radius * hand.radius
            let k = camera.position.z / (camera.position.z - SyntheticRayCaster.handHeight)
            handViewX = camera.position.x + (hand.centre.x - camera.position.x) * k
            handViewY = camera.position.y + (hand.centre.y - camera.position.y) * k
            handViewRadius = hand.radius * k
        } else {
            hasHand = false
            handX = 0; handY = 0; handRadius2 = 0
            handViewX = 0; handViewY = 0; handViewRadius = 0
        }
        handColour = SyntheticDartSolid.pack(SyntheticRayCaster.handColour)

        var lit: [UInt32] = [], dark: [UInt32] = []
        let tint = SyntheticRayCaster.shadowTint * strength
        func darken(_ value: UInt8, _ factor: Double) -> UInt8 {
            UInt8(min(255, max(0, (Double(value) * factor).rounded())))
        }
        for paint in SyntheticBoard.Paint.allCases {
            let colour = paint.colour
            lit.append(SyntheticDartSolid.pack(colour))
            dark.append(SyntheticDartSolid.pack(SIMD3(darken(colour.x, tint.x), darken(colour.y, tint.y), darken(colour.z, tint.z))))
        }
        palette = lit
        shadowPalette = dark
    }

    // MARK: Shading

    /// Colour seen along the ray `C + t·d`.
    @inline(__always)
    private func shade(_ dx: Double, _ dy: Double, _ dz: Double) -> UInt32 {
        // A ray that does not go down to the board plane sees the wall.
        if dz > -1e-12 { return palette[0] }
        let t0 = -cz / dz
        let x0 = cx + t0 * dx, y0 = cy + t0 * dy
        // Raised wires: a ray that meets one stops there.
        var limit = t0
        var onWire = false
        var xw = x0, yw = y0
        if wireHeight > 0 {
            let tw = (wireHeight - cz) / dz
            xw = cx + tw * dx
            yw = cy + tw * dy
            if board.isWire(x: xw, y: yw) {
                onWire = true
                limit = tw
            }
        }

        // Darts and hand: the nearest one along the ray, before the wire or the board. Two darts that interpenetrate can
        // be entered at the same distance (their flight plates may share a plane): the larger packed colour wins
        // then, so that the order of the darts in the scene never matters.
        var nearest = Double.infinity
        var colour: UInt32 = 0
        let dartCount = solids.count
        var index = 0
        while index < dartCount {
            if viewBody[index].contains(x: x0, y: y0) {
                var part: UInt32 = 0
                let t = solids[index].hitBody(px: cx, py: cy, pz: cz, dx: dx, dy: dy, dz: dz, limit: limit, colour: &part)
                if t >= 0 && (t < nearest || (t == nearest && part > colour)) {
                    nearest = t
                    colour = part
                }
            }
            if viewFlight[index].contains(x: x0, y: y0) {
                let t = solids[index].hitFlight(px: cx, py: cy, pz: cz, dx: dx, dy: dy, dz: dz, limit: limit)
                let part = solids[index].flightColour
                if t >= 0 && (t < nearest || (t == nearest && part > colour)) {
                    nearest = t
                    colour = part
                }
            }
            index += 1
        }
        if hasHand {
            let th = (SyntheticRayCaster.handHeight - cz) / dz
            if th < nearest && th <= limit {
                let hx = cx + th * dx - handX, hy = cy + th * dy - handY
                if hx * hx + hy * hy <= handRadius2 {
                    nearest = th
                    colour = handColour
                }
            }
        }
        if nearest < Double.infinity { return colour }

        // Wires, then the board.
        let paint: SyntheticBoard.Paint
        var sx = x0, sy = y0, sz = 0.0
        let onWirePlane = onWire
        if onWire {
            paint = .wire
            sx = xw; sy = yw; sz = wireHeight
        } else if wireHeight > 0 {
            paint = board.surface(x: x0, y: y0)
        } else {
            paint = board.paint(x: x0, y: y0)
        }
        if hasLight, lightZ > sz {
            // In shadow when the segment to the lamp touches a dart.
            let lx = lightX - sx, ly = lightY - sy, lz = lightZ - sz
            index = 0
            while index < dartCount {
                let bodyPrint = onWirePlane ? wireShadowBody[index] : shadowBody[index]
                if bodyPrint.contains(x: sx, y: sy) {
                    var part: UInt32 = 0
                    if solids[index].hitBody(px: sx, py: sy, pz: sz, dx: lx, dy: ly, dz: lz, limit: 1, colour: &part) >= 0 {
                        return shadowPalette[Int(paint.rawValue)]
                    }
                }
                let flightPrint = onWirePlane ? wireShadowFlight[index] : shadowFlight[index]
                if flightPrint.contains(x: sx, y: sy) {
                    if solids[index].hitFlight(px: sx, py: sy, pz: sz, dx: lx, dy: ly, dz: lz, limit: 1) >= 0 {
                        return shadowPalette[Int(paint.rawValue)]
                    }
                }
                index += 1
            }
        }
        return palette[Int(paint.rawValue)]
    }

    /// The colour shared by every ray that meets the board plane within `radius` mm of the ray `C + t·d`,
    /// or -1 when those rays may see different things.
    @inline(__always)
    private func uniformColour(_ dx: Double, _ dy: Double, _ dz: Double, radius: Double) -> Int64 {
        if dz > -1e-12 { return -1 }
        let t0 = -cz / dz
        let x0 = cx + t0 * dx, y0 = cy + t0 * dy
        // A dart nearby: its outline may cross the block.
        let dartCount = solids.count
        var index = 0
        while index < dartCount {
            if viewBody[index].isWithin(radius, x: x0, y: y0) || viewFlight[index].isWithin(radius, x: x0, y: y0) {
                return -1
            }
            index += 1
        }
        if hasHand {
            let hx = x0 - handViewX, hy = y0 - handViewY
            let distance = (hx * hx + hy * hy).squareRoot()
            if distance < handViewRadius - radius { return Int64(handColour) }
            if distance <= handViewRadius + radius { return -1 }
        }
        let paint: SyntheticBoard.Paint
        var sx = x0, sy = y0
        var onWirePlane = false
        if wireHeight > 0 {
            let tw = (wireHeight - cz) / dz
            let xw = cx + tw * dx, yw = cy + tw * dy
            if board.wireClearance(x: xw, y: yw) <= radius || board.surfaceClearance(x: x0, y: y0) <= radius { return -1 }
            if board.isWire(x: xw, y: yw) {
                paint = .wire
                sx = xw; sy = yw
                onWirePlane = true
            } else {
                paint = board.surface(x: x0, y: y0)
            }
        } else {
            if board.paintClearance(x: x0, y: y0) <= radius { return -1 }
            paint = board.paint(x: x0, y: y0)
        }
        if hasLight {
            // A shadow nearby: its outline may cross the block.
            index = 0
            while index < dartCount {
                let bodyPrint = onWirePlane ? wireShadowBody[index] : shadowBody[index]
                let flightPrint = onWirePlane ? wireShadowFlight[index] : shadowFlight[index]
                if bodyPrint.isWithin(radius, x: sx, y: sy) || flightPrint.isWithin(radius, x: sx, y: sy) { return -1 }
                index += 1
            }
        }
        return Int64(palette[Int(paint.rawValue)])
    }

    /// Pixels being written by one band: `base` holds the pixel `(originX, originY)` of the image, rows are
    /// `stride` pixels apart.
    private struct Target {
        var base: UnsafeMutablePointer<UInt8>
        var originX: Int
        var originY: Int
        var stride: Int

        @inline(__always)
        func pixel(_ x: Int, _ y: Int) -> UnsafeMutablePointer<UInt8> {
            base + ((y - originY) * stride + (x - originX)) * 3
        }
    }

    /// Writes `colour` into the pixels `x ..< x + size`, `y ..< y + size` that lie inside `limit`.
    @inline(__always)
    private func fill(_ target: Target, x: Int, y: Int, size: Int, limit: SyntheticPixelBox, colour: UInt32) {
        let x1 = x + size < limit.x1 ? x + size : limit.x1, y1 = y + size < limit.y1 ? y + size : limit.y1
        guard x < x1, y < y1 else { return }
        let first = target.pixel(x, y)
        let red = UInt8(colour & 0xFF), green = UInt8((colour >> 8) & 0xFF), blue = UInt8((colour >> 16) & 0xFF)
        let bytes = (x1 - x) * 3
        var offset = 0
        while offset < bytes {
            first[offset] = red
            first[offset + 1] = green
            first[offset + 2] = blue
            offset += 3
        }
        var row = y + 1
        while row < y1 {
            target.pixel(x, row).update(from: first, count: bytes)
            row += 1
        }
    }

    /// Renders the rows of `box` in concurrent bands of whole blocks and copies them into `pixels`, an image of
    /// `imageWidth` pixels per row. `render` fills one band of `target`, inside `limit`.
    private func renderBands(of box: SyntheticPixelBox, into pixels: inout [UInt8], imageWidth: Int,
                             _ render: @Sendable (SyntheticRayCaster, Target, SyntheticPixelBox) -> Void) {
        let side = SyntheticRayCaster.blockSide
        let span = box.x1 - box.x0
        guard span > 0, box.y1 > box.y0 else { return }
        let caster = self
        let bands = ImagingParallel.bands(of: box.y0..<box.y1, minimumBand: side, alignment: side)
        let parts = ImagingParallel.map(bands) { band -> [UInt8] in
            var part = [UInt8](repeating: 0, count: band.count * span * 3)
            part.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                let target = Target(base: base, originX: box.x0, originY: band.lowerBound, stride: span)
                render(caster, target, SyntheticPixelBox(x0: box.x0, y0: band.lowerBound, x1: box.x1, y1: band.upperBound))
            }
            return part
        }
        for (band, part) in zip(bands, parts) {
            ImagingParallel.place(part, band: band, partRowBytes: span * 3, into: &pixels, rowBytes: imageWidth * 3,
                                  firstByte: box.x0 * 3)
        }
    }

    // MARK: Camera image

    /// The camera image: 3x3 rays per pixel, averaged. No blur, shift, gain or noise.
    func cameraImage() -> SyntheticBaseImage {
        let w = width, h = height
        var pixels = RGBImage(width: w, height: h, fill: SyntheticBoard.Paint.wall.colour).pixels
        let nothing = SyntheticPixelBox(x0: 0, y0: 0, x1: 0, y1: 0)
        guard w > 0, h > 0, focalX != 0, focalY != 0 else {
            return SyntheticBaseImage(image: RGBImage(width: w, height: h, pixels: pixels), content: nothing)
        }
        let full = SyntheticPixelBox(x0: 0, y0: 0, x1: w, y1: h)

        // Everything that is not plain wall: the board, the darts, their shadows, the hand.
        var content = imageBox(ofDisc: board.outerRadius, at: 0) ?? full
        if wireHeight > 0 {
            content = content.union(imageBox(ofDisc: board.wireOuterRadius, at: wireHeight) ?? full)
        }
        for index in solids.indices {
            content = content.union(imageBox(of: viewBody[index], at: 0) ?? full)
            content = content.union(imageBox(of: viewFlight[index], at: 0) ?? full)
            if hasLight {
                content = content.union(imageBox(of: shadowBody[index], at: 0) ?? full)
                content = content.union(imageBox(of: shadowFlight[index], at: 0) ?? full)
                if wireHeight > 0 {
                    content = content.union(imageBox(of: wireShadowBody[index], at: wireHeight) ?? full)
                    content = content.union(imageBox(of: wireShadowFlight[index], at: wireHeight) ?? full)
                }
            }
        }
        if hasHand {
            let disc = SyntheticFootprint(x0: handViewX, y0: handViewY, x1: handViewX, y1: handViewY,
                                          radius: handViewRadius, bounded: true)
            content = content.union(imageBox(of: disc, at: 0) ?? full)
        }
        guard !content.isEmpty else {
            return SyntheticBaseImage(image: RGBImage(width: w, height: h, pixels: pixels), content: content)
        }

        let reach = boardMillimetresPerPixel(in: content)
        let side = SyntheticRayCaster.blockSide
        renderBands(of: content, into: &pixels, imageWidth: w) { caster, target, limit in
            var y = limit.y0
            while y < limit.y1 {
                var x = limit.x0
                while x < limit.x1 {
                    caster.renderCameraBlock(target, x: x, y: y, size: side, limit: limit, reach: reach)
                    x += side
                }
                y += side
            }
        }
        return SyntheticBaseImage(image: RGBImage(width: w, height: h, pixels: pixels), content: content)
    }

    /// Renders the pixels of one block that lie inside `limit`. `reach` is the largest distance on the board,
    /// in mm, between the rays of two pixels one pixel apart.
    private func renderCameraBlock(_ target: Target, x: Int, y: Int, size: Int, limit: SyntheticPixelBox, reach: Double) {
        if x >= limit.x1 || y >= limit.y1 { return }
        let inverseFocalX = 1 / focalX, inverseFocalY = 1 / focalY
        // Centre of the block; its samples are within (half + 1/3) pixels of it on each axis.
        let half = Double(size - 1) / 2
        let xc = (Double(x) + half - principalX) * inverseFocalX
        let yc = (Double(y) + half - principalY) * inverseFocalY
        let dx = xc * rightX + yc * downX + forwardX
        let dy = xc * rightY + yc * downY + forwardY
        let dz = xc * rightZ + yc * downZ + forwardZ
        let radius = (half + 1.0 / 3.0) * 1.4142135623730951 * reach
        let uniform = uniformColour(dx, dy, dz, radius: radius)
        if uniform >= 0 {
            fill(target, x: x, y: y, size: size, limit: limit, colour: UInt32(uniform))
            return
        }
        if size > 1 {
            let smaller = size / 2
            renderCameraBlock(target, x: x, y: y, size: smaller, limit: limit, reach: reach)
            renderCameraBlock(target, x: x + smaller, y: y, size: smaller, limit: limit, reach: reach)
            renderCameraBlock(target, x: x, y: y + smaller, size: smaller, limit: limit, reach: reach)
            renderCameraBlock(target, x: x + smaller, y: y + smaller, size: smaller, limit: limit, reach: reach)
            return
        }
        // One pixel with an edge in it: nine rays.
        var red: UInt32 = 0, green: UInt32 = 0, blue: UInt32 = 0
        var sub = 0
        while sub < 9 {
            let offsetX = Double(sub % 3 - 1) / 3, offsetY = Double(sub / 3 - 1) / 3
            let sxc = (Double(x) + offsetX - principalX) * inverseFocalX
            let syc = (Double(y) + offsetY - principalY) * inverseFocalY
            let colour = shade(sxc * rightX + syc * downX + forwardX,
                               sxc * rightY + syc * downY + forwardY,
                               sxc * rightZ + syc * downZ + forwardZ)
            red += colour & 0xFF
            green += (colour >> 8) & 0xFF
            blue += (colour >> 16) & 0xFF
            sub += 1
        }
        let pixel = target.pixel(x, y)
        // (sum + 4) / 9, exact for sums up to 9 * 255.
        pixel[0] = UInt8(((red + 4) * 7282) >> 16)
        pixel[1] = UInt8(((green + 4) * 7282) >> 16)
        pixel[2] = UInt8(((blue + 4) * 7282) >> 16)
    }

    /// Upper bound, with a margin, of the distance on the board plane between the rays of two pixels one pixel
    /// apart, anywhere in `box`. Infinite when a ray of the box does not reach the board plane: no block is then
    /// taken as uniform.
    private func boardMillimetresPerPixel(in box: SyntheticPixelBox) -> Double {
        func boardPoint(_ u: Double, _ v: Double) -> SIMD2<Double>? {
            let xc = (u - principalX) / focalX, yc = (v - principalY) / focalY
            let dx = xc * rightX + yc * downX + forwardX
            let dy = xc * rightY + yc * downY + forwardY
            let dz = xc * rightZ + yc * downZ + forwardZ
            guard dz < -1e-9 else { return nil }
            let t = -cz / dz
            return SIMD2(cx + t * dx, cy + t * dy)
        }
        var largest = 0.0
        let steps = 8
        for j in 0...steps {
            for i in 0...steps {
                let u = Double(box.x0) - 1 + Double(box.x1 - box.x0 + 1) * Double(i) / Double(steps)
                let v = Double(box.y0) - 1 + Double(box.y1 - box.y0 + 1) * Double(j) / Double(steps)
                guard let p = boardPoint(u, v), let px = boardPoint(u + 1, v), let py = boardPoint(u, v + 1) else {
                    return .infinity
                }
                // Largest singular value of the 2x2 matrix whose columns are the two steps.
                let a = px - p, b = py - p
                let aa = simd_dot(a, a), bb = simd_dot(b, b), ab = simd_dot(a, b)
                let stretch = ((aa + bb + ((aa - bb) * (aa - bb) + 4 * ab * ab).squareRoot()) / 2).squareRoot()
                guard stretch.isFinite else { return .infinity }
                if stretch > largest { largest = stretch }
            }
        }
        return largest * 1.2
    }

    // MARK: Canvas image

    /// The same scene seen in the canvas: one ray per canvas pixel, from the camera centre through the metric
    /// board point of the pixel. Only the pixels of `box` are rendered; the others stay black.
    func canvasImage(box requested: SyntheticPixelBox) -> RGBImage {
        let side = BoardCanvas.side
        var pixels = [UInt8](repeating: 0, count: side * side * 3)
        let box = SyntheticPixelBox(x0: max(0, requested.x0), y0: max(0, requested.y0),
                                    x1: min(side, requested.x1), y1: min(side, requested.y1))
        guard !box.isEmpty, cz > 0 else { return RGBImage(width: side, height: side, pixels: pixels) }
        let block = SyntheticRayCaster.blockSide
        renderBands(of: box, into: &pixels, imageWidth: side) { caster, target, limit in
            var y = limit.y0
            while y < limit.y1 {
                var x = limit.x0
                while x < limit.x1 {
                    caster.renderCanvasBlock(target, x: x, y: y, size: block, limit: limit)
                    x += block
                }
                y += block
            }
        }
        return RGBImage(width: side, height: side, pixels: pixels)
    }

    private func renderCanvasBlock(_ target: Target, x: Int, y: Int, size: Int, limit: SyntheticPixelBox) {
        if x >= limit.x1 || y >= limit.y1 { return }
        let scale = BoardCanvas.pixelsPerMillimetre, extent = BoardCanvas.halfExtent
        let half = Double(size - 1) / 2
        // Metric board point of the centre of the block; the ray goes from the camera centre through it.
        let bx = -extent + (Double(x) + half + 0.5) / scale
        let by = extent - (Double(y) + half + 0.5) / scale
        let dx = bx - cx, dy = by - cy, dz = -cz
        if size == 1 {
            let colour = shade(dx, dy, dz)
            let pixel = target.pixel(x, y)
            pixel[0] = UInt8(colour & 0xFF)
            pixel[1] = UInt8((colour >> 8) & 0xFF)
            pixel[2] = UInt8((colour >> 16) & 0xFF)
            return
        }
        // The pixel centres of the block are within `half` pixels of its centre on each axis.
        let radius = half * 1.4142135623730951 / scale + 1e-6
        let uniform = uniformColour(dx, dy, dz, radius: radius)
        if uniform >= 0 {
            fill(target, x: x, y: y, size: size, limit: limit, colour: UInt32(uniform))
            return
        }
        let smaller = size / 2
        renderCanvasBlock(target, x: x, y: y, size: smaller, limit: limit)
        renderCanvasBlock(target, x: x + smaller, y: y, size: smaller, limit: limit)
        renderCanvasBlock(target, x: x, y: y + smaller, size: smaller, limit: limit)
        renderCanvasBlock(target, x: x + smaller, y: y + smaller, size: smaller, limit: limit)
    }

    // MARK: Bounding boxes

    /// Pixels (with a margin of two) that can show a point of the disc of radius `radius` in the plane `z = plane`;
    /// nil when part of the disc is behind the camera.
    private func imageBox(ofDisc radius: Double, at plane: Double) -> SyntheticPixelBox? {
        var points: [SIMD3<Double>] = []
        let samples = 720
        // The polygon circumscribed to the circle, so that its image contains the image of the disc.
        let outer = radius / cos(Double.pi / Double(samples))
        for index in 0..<samples {
            let angle = 2 * Double.pi * Double(index) / Double(samples)
            points.append(SIMD3(outer * cos(angle), outer * sin(angle), plane))
        }
        return imageBox(of: points)
    }

    /// Pixels that can show a point of a footprint lying in the plane `z = plane`; nil when it is unbounded.
    private func imageBox(of footprint: SyntheticFootprint, at plane: Double) -> SyntheticPixelBox? {
        guard footprint.bounded else { return nil }
        var ex = footprint.x1 - footprint.x0, ey = footprint.y1 - footprint.y0
        let length = (ex * ex + ey * ey).squareRoot()
        if length > 0 {
            ex /= length
            ey /= length
        } else {
            ex = 1
            ey = 0
        }
        let r = footprint.radius
        // Corners of the oriented rectangle around the capsule.
        let corners: [SIMD3<Double>] = [
            SIMD3(footprint.x0 - r * ex - r * ey, footprint.y0 - r * ey + r * ex, plane),
            SIMD3(footprint.x0 - r * ex + r * ey, footprint.y0 - r * ey - r * ex, plane),
            SIMD3(footprint.x1 + r * ex - r * ey, footprint.y1 + r * ey + r * ex, plane),
            SIMD3(footprint.x1 + r * ex + r * ey, footprint.y1 + r * ey - r * ex, plane),
        ]
        return imageBox(of: corners)
    }

    /// Bounding box, clipped to the image, of the projections of the corners of a convex polygon; nil when a corner
    /// is behind the camera (the projection is then unbounded).
    private func imageBox(of points: [SIMD3<Double>]) -> SyntheticPixelBox? {
        var minU = Double.infinity, minV = Double.infinity, maxU = -Double.infinity, maxV = -Double.infinity
        for point in points {
            let image = camera.project(point)
            guard image.x.isFinite, image.y.isFinite else { return nil }
            minU = min(minU, image.x); maxU = max(maxU, image.x)
            minV = min(minV, image.y); maxV = max(maxV, image.y)
        }
        guard minU <= maxU, minV <= maxV else { return nil }
        let margin = 2.0
        let x0 = max(0, min(Double(width), (minU - margin).rounded(.down)))
        let y0 = max(0, min(Double(height), (minV - margin).rounded(.down)))
        let x1 = max(0, min(Double(width), (maxU + margin).rounded(.up) + 1))
        let y1 = max(0, min(Double(height), (maxV + margin).rounded(.up) + 1))
        return SyntheticPixelBox(x0: Int(x0), y0: Int(y0), x1: Int(x1), y1: Int(y1))
    }
}
