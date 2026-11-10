import Foundation
import Testing
import DartCore
@testable import DartVision

/// Morphology and connected components on small known masks (B1), and the run-length canvas mask.
@Suite struct ImagingMorphologyTests {
    /// A mask drawn as text: `#` is set, anything else is clear. Rows must have the same length.
    private func mask(_ rows: [String]) -> GrayImage {
        let width = rows.first?.count ?? 0
        var pixels: [UInt8] = []
        for row in rows {
            precondition(row.count == width, "ragged mask")
            pixels += row.map { $0 == "#" ? 255 : 0 }
        }
        return GrayImage(width: width, height: rows.count, pixels: pixels)
    }

    /// The labels of a labelling as text: `.` for the background, then 1...9.
    private func picture(_ components: ConnectedComponents) -> [String] {
        (0..<components.height).map { y in
            String((0..<components.width).map { x -> Character in
                let label = components.label(x: x, y: y)
                return label == 0 ? "." : Character(String(label))
            })
        }
    }

    /// The mask as text, `#` for every non-zero pixel.
    private func text(_ image: GrayImage) -> [String] {
        (0..<image.height).map { y in
            String((0..<image.width).map { x in image[x, y] != 0 ? "#" : "." })
        }
    }

    // MARK: B1

    @Test func b1_labelsAndAreas() {
        let image = mask([
            "##....#...",
            "##...#....",
            "....#....#",
            "#.......##",
            "#..###....",
            "...#.#..#.",
            "...###..#.",
        ])
        let components = ConnectedComponents(image)
        // 8-connectivity: the diagonal staircase is one component; labels follow the raster order of first pixels.
        #expect(picture(components) == [
            "11....2...",
            "11...2....",
            "....2....3",
            "4.......33",
            "4..555....",
            "...5.5..6.",
            "...555..6.",
        ])
        #expect(components.components.map(\.pixelCount) == [4, 3, 3, 2, 8, 2])
        #expect(components.components.map(\.label) == [1, 2, 3, 4, 5, 6])
        let ring = components.components[4]
        #expect(ring.minX == 3 && ring.maxX == 5 && ring.minY == 4 && ring.maxY == 6 && ring.width == 3 && ring.height == 3)
        #expect(ring.centroid == SIMD2(4, 5))
        let staircase = components.components[1]
        #expect(staircase.minX == 4 && staircase.maxX == 6 && staircase.minY == 0 && staircase.maxY == 2)
        // Masks of components.
        #expect(text(components.mask(of: 6)) == [
            "..........", "..........", "..........", "..........", "..........", "........#.", "........#.",
        ])
        #expect(components.mask { $0.pixelCount >= 4 }.pixels.filter { $0 == 255 }.count == 12)
        #expect(components.label(x: -1, y: 0) == 0 && components.label(x: 0, y: 7) == 0)
    }

    @Test func b1_shapesThatMeetLateAreMerged() {
        // A U and a W: their arms open new provisional labels that only meet at the bottom.
        let image = mask([
            "#...#.#.#.#",
            "#...#.#.#.#",
            "#...#.#.#.#",
            "#####.#####",
        ])
        let components = ConnectedComponents(image)
        #expect(picture(components) == [
            "1...1.2.2.2",
            "1...1.2.2.2",
            "1...1.2.2.2",
            "11111.22222",
        ])
        #expect(components.components.map(\.pixelCount) == [11, 14])
        // A spiral whose arms merge in the opposite order.
        let spiral = ConnectedComponents(mask([
            "#.#.#",
            "#.#.#",
            "#.###",
            "#....",
            "#####",
        ]))
        #expect(spiral.components.count == 2)
        #expect(picture(spiral) == ["1.2.2", "1.2.2", "1.222", "1....", "11111"])
        // A checkerboard is one component with 8-connectivity.
        let checker = ConnectedComponents(mask(["#.#.#", ".#.#.", "#.#.#", ".#.#."]))
        #expect(checker.components.count == 1 && checker.components[0].pixelCount == 10)
        // Empty and full masks.
        #expect(ConnectedComponents(mask(["....", "...."])).components.isEmpty)
        let full = ConnectedComponents(GrayImage(width: 6, height: 5, fill: 1))
        #expect(full.components.count == 1 && full.components[0].pixelCount == 30)
        #expect(ConnectedComponents(GrayImage(width: 0, height: 0, fill: 0)).components.isEmpty)
    }

    @Test func b1_openingRemovesTwoPixelLines() {
        let image = mask([
            "..............",
            ".##.......###.",
            ".##.......###.",
            ".##.......###.",
            ".##.......###.",
            "..............",
            "######........",
            "######........",
            "..............",
            "...#####......",
            "...#####......",
            "...#####......",
            "..............",
        ])
        let opened = Morphology.open(image, radius: 1)
        // Lines 2 px wide (the vertical bar, the horizontal bar) vanish; a 3 px bar and a 3x5 block survive whole.
        #expect(text(opened) == [
            "..............",
            "..........###.",
            "..........###.",
            "..........###.",
            "..........###.",
            "..............",
            "..............",
            "..............",
            "..............",
            "...#####......",
            "...#####......",
            "...#####......",
            "..............",
        ])
        #expect(Set(opened.pixels) == [0, 255])
        // Erosion and dilation on their own.
        let dot = mask([".....", ".....", "..#..", ".....", "....."])
        #expect(text(Morphology.dilate(dot, radius: 1)) == [".....", ".###.", ".###.", ".###.", "....."])
        #expect(text(Morphology.erode(Morphology.dilate(dot, radius: 1), radius: 1)) == text(dot))
        #expect(text(Morphology.dilate(dot, radius: 2)) == Array(repeating: "#####", count: 5))
        // Along the border, an opening never adds a pixel and an erosion treats the outside as set.
        let edge = mask(["###.", "###.", "###.", "...."])
        #expect(text(Morphology.erode(edge, radius: 1)) == ["##..", "##..", "....", "...."])
        #expect(text(Morphology.open(edge, radius: 1)) == text(edge))
        // Radius 0 only binarises.
        #expect(Morphology.open(GrayImage(width: 2, height: 1, pixels: [0, 7]), radius: 0).pixels == [0, 255])
    }

    @Test func b1_closingFillsSixPixelGaps() {
        // Four blocks 3 px tall, at least 4 px from every border. Gaps: 6 px (columns 8 to 13), 4 px (18 to 21),
        // 7 px (26 to 32).
        let empty = String(repeating: ".", count: 41)
        let blocks = "...." + "####" + "......" + "####" + "...." + "####" + "......." + "####" + "...."
        let image = mask([empty, empty, empty, empty, blocks, blocks, blocks, empty, empty, empty, empty])
        let closed = Morphology.close(image, radius: 3)
        let joined = "...." + String(repeating: "#", count: 22) + "......." + "####" + "...."
        #expect(text(closed) == [empty, empty, empty, empty, joined, joined, joined, empty, empty, empty, empty])
        // Closing never removes a pixel.
        #expect(zip(image.pixels, closed.pixels).allSatisfy { $0 == 0 || $1 == 255 })
        // A 6x6 hole inside a block is filled; a 7x7 one is not.
        var hole = [String](repeating: String(repeating: "#", count: 14), count: 14)
        for y in 4..<10 {
            hole[y] = "####" + String(repeating: ".", count: 6) + "####"
        }
        #expect(Set(Morphology.close(mask(hole), radius: 3).pixels) == [255])
        var bigger = [String](repeating: String(repeating: "#", count: 15), count: 15)
        for y in 4..<11 {
            bigger[y] = "####" + String(repeating: ".", count: 7) + "####"
        }
        let partly = Morphology.close(mask(bigger), radius: 3)
        #expect(partly[7, 7] == 0 && partly[4, 4] == 0 && partly[3, 3] == 255)
        #expect(text(partly) == text(mask(bigger)))
    }

    // MARK: Canvas mask

    @Test func canvasMask_runsAreaAndMembership() throws {
        var image = GrayImage(width: BoardCanvas.side, height: BoardCanvas.side, fill: 0)
        for y in 600..<610 {
            for x in 630..<650 {
                image[x, y] = 255
            }
        }
        let mask = CanvasMask(image)
        #expect(!mask.isEmpty && CanvasMask().isEmpty && CanvasMask().area == 0)
        #expect(mask.pixelCount == 200 && mask.area == 50 && mask.runCount == 10)
        let drawn = mask.makeImage() == image
        #expect(drawn)
        // Pixel (639, 600) holds the board point x = −0.25, y = 19.75.
        #expect(mask.contains(BoardCanvas.boardPoint(x: 639, y: 600)) && mask.contains(x: 649, y: 609))
        #expect(!mask.contains(BoardCanvas.boardPoint(x: 650, y: 600)) && !mask.contains(x: 629, y: 605))
        #expect(!mask.contains(BoardPoint(x: .nan, y: 0)) && !mask.contains(BoardPoint(x: 1000, y: 0)))
        #expect(mask.boundingBox?.minX == 630 && mask.boundingBox?.maxX == 649 && mask.boundingBox?.minY == 600 && mask.boundingBox?.maxY == 609)
        // Equal pixels, equal masks: runs given in any order and overlapping come back canonical.
        let shuffled = CanvasMask(runs: [CanvasMask.Run(y: 5, x0: 10, x1: 20), CanvasMask.Run(y: 1, x0: 3, x1: 4),
                                         CanvasMask.Run(y: 5, x0: 15, x1: 30), CanvasMask.Run(y: 5, x0: 30, x1: 31),
                                         CanvasMask.Run(y: -3, x0: 0, x1: 5), CanvasMask.Run(y: 7, x0: 1270, x1: 1500)])
        #expect(shuffled.runs == [CanvasMask.Run(y: 1, x0: 3, x1: 4), CanvasMask.Run(y: 5, x0: 10, x1: 31),
                                  CanvasMask.Run(y: 7, x0: 1270, x1: 1280)])
        // JSON round trip, and a damaged file is brought back inside the canvas.
        let decoded = try JSONDecoder().decode(CanvasMask.self, from: JSONEncoder().encode(mask))
        #expect(decoded == mask)
        let damaged = try JSONDecoder().decode(CanvasMask.self, from: Data(#"{"spans":[3,5,2,1,1270,9999,9999,0,4]}"#.utf8))
        #expect(damaged.runs == [CanvasMask.Run(y: 1, x0: 1270, x1: 1280)])
    }

    @Test func canvasMask_dilationUnionIntersection() {
        let dot = CanvasMask(runs: [CanvasMask.Run(y: 640, x0: 640, x1: 641)])
        // 2 mm = 4 canvas pixels: every pixel whose centre is within 4 px, a disc of 49 pixels.
        let disc = dot.dilated(by: 2)
        #expect(disc.pixelCount == 49)
        #expect(disc.contains(x: 644, y: 640) && !disc.contains(x: 645, y: 640) && disc.contains(x: 643, y: 642) && !disc.contains(x: 643, y: 643))
        #expect(dot.dilated(by: 0) == dot && dot.dilated(by: -1) == dot && dot.dilated(by: .nan) == dot)
        // An enormous dilation covers the canvas without trapping.
        let everything = dot.dilated(by: 1e12)
        #expect(everything.pixelCount == BoardCanvas.side * BoardCanvas.side)
        // Near the border the disc is clipped.
        let corner = CanvasMask(runs: [CanvasMask.Run(y: 0, x0: 0, x1: 1)]).dilated(by: 1)
        #expect(corner.pixelCount == 6)
        // Union, intersection, difference, overlap.
        let a = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 0, x1: 10), CanvasMask.Run(y: 11, x0: 5, x1: 8)])
        let b = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 10, x1: 12), CanvasMask.Run(y: 11, x0: 7, x1: 9), CanvasMask.Run(y: 12, x0: 0, x1: 1)])
        #expect(a.union(b).runs == [CanvasMask.Run(y: 10, x0: 0, x1: 12), CanvasMask.Run(y: 11, x0: 5, x1: 9), CanvasMask.Run(y: 12, x0: 0, x1: 1)])
        #expect(a.union(CanvasMask()) == a && CanvasMask().union(b) == b)
        #expect(a.intersects(b))
        #expect(a.intersection(b).runs == [CanvasMask.Run(y: 11, x0: 7, x1: 8)])
        let c = CanvasMask(runs: [CanvasMask.Run(y: 10, x0: 10, x1: 12)])
        #expect(!a.intersects(c) && a.intersection(c).isEmpty)
        #expect(a.subtracting(b).runs == [CanvasMask.Run(y: 10, x0: 0, x1: 10), CanvasMask.Run(y: 11, x0: 5, x1: 7)])
        #expect(CanvasMask(runs: [CanvasMask.Run(y: 3, x0: 0, x1: 20)]).subtracting(CanvasMask(runs: [CanvasMask.Run(y: 3, x0: 4, x1: 6), CanvasMask.Run(y: 3, x0: 10, x1: 12)])).runs
                == [CanvasMask.Run(y: 3, x0: 0, x1: 4), CanvasMask.Run(y: 3, x0: 6, x1: 10), CanvasMask.Run(y: 3, x0: 12, x1: 20)])
        #expect(!CanvasMask().intersects(a) && !a.intersects(CanvasMask()))
        // Row offsets index the first run of each row.
        let offsets = a.union(b).rowOffsets
        #expect(offsets.count == BoardCanvas.side + 1 && offsets[10] == 0 && offsets[11] == 1 && offsets[12] == 2 && offsets[13] == 3)
        #expect(offsets[BoardCanvas.side] == 3)
    }
}
