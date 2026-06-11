import AppKit

enum RefineError: Error, CustomStringConvertible {
    case usage
    case loadImage(String)
    case makeImage
    case writeFailed(String)

    var description: String {
        switch self {
        case .usage:
            return usageText
        case .loadImage(let path):
            return "Failed to load image: \(path)"
        case .makeImage:
            return "Failed to create image"
        case .writeFailed(let path):
            return "Failed to write output: \(path)"
        }
    }
}

let usageText = """
Usage:
  swift refine_alpha.swift --input <png> --output <png> [options]

Options:
  --left-clear pixels  Make dark pixels transparent inside the left edge width.
  --left-curve-clear points
                       Clear everything left of a y:x curve, for example
                       0:168,90:156,220:132,360:112,520:72,640:24.
  --trim               Trim fully transparent borders with small padding.
"""

struct Options {
    var input: String?
    var output: String?
    var leftClearWidth = 0
    var leftCurve: [(Double, Double)] = []
    var trim = false
}

func parseCurve(_ value: String) throws -> [(Double, Double)] {
    let pairs = value.split(separator: ",").map(String.init)
    let points = try pairs.map { pair -> (Double, Double) in
        let parts = pair.split(separator: ":").map(String.init)
        guard parts.count == 2, let y = Double(parts[0]), let x = Double(parts[1]) else {
            throw RefineError.usage
        }
        return (y, x)
    }.sorted { $0.0 < $1.0 }
    return points
}

func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        switch args[index] {
        case "--input":
            index += 1
            guard index < args.count else { throw RefineError.usage }
            options.input = args[index]
        case "--output":
            index += 1
            guard index < args.count else { throw RefineError.usage }
            options.output = args[index]
        case "--left-clear":
            index += 1
            guard index < args.count, let value = Int(args[index]) else { throw RefineError.usage }
            options.leftClearWidth = max(0, value)
        case "--left-curve-clear":
            index += 1
            guard index < args.count else { throw RefineError.usage }
            options.leftCurve = try parseCurve(args[index])
        case "--trim":
            options.trim = true
        case "--help", "-h":
            print(usageText)
            exit(0)
        default:
            throw RefineError.usage
        }
        index += 1
    }
    guard options.input != nil, options.output != nil else {
        throw RefineError.usage
    }
    return options
}

func cgImage(from path: String) throws -> CGImage {
    guard let source = NSImage(contentsOfFile: path),
          let tiff = source.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let image = bitmap.cgImage else {
        throw RefineError.loadImage(path)
    }
    return image
}

func imageBuffer(from image: CGImage) throws -> (pixels: [UInt8], width: Int, height: Int, colorSpace: CGColorSpace) {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw RefineError.makeImage
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (pixels, width, height, colorSpace)
}

func makeImage(from pixels: inout [UInt8], width: Int, height: Int, colorSpace: CGColorSpace) throws -> CGImage {
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        throw RefineError.makeImage
    }
    return image
}

func clearDarkLeftEdge(_ image: CGImage, width clearWidth: Int) throws -> CGImage {
    guard clearWidth > 0 else { return image }
    var (pixels, width, height, colorSpace) = try imageBuffer(from: image)
    for y in 0..<height {
        for x in 0..<min(width, clearWidth) {
            let offset = (y * width + x) * 4
            guard pixels[offset + 3] > 0 else { continue }
            let brightness = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            if brightness < 95 {
                pixels[offset + 3] = 0
            }
        }
    }
    return try makeImage(from: &pixels, width: width, height: height, colorSpace: colorSpace)
}

func boundaryX(forY y: Int, points: [(Double, Double)]) -> Double {
    guard !points.isEmpty else { return 0 }
    let yValue = Double(y)
    if yValue <= points[0].0 {
        return points[0].1
    }
    for index in 1..<points.count {
        let previous = points[index - 1]
        let next = points[index]
        if yValue <= next.0 {
            let t = (yValue - previous.0) / (next.0 - previous.0)
            return previous.1 + (next.1 - previous.1) * t
        }
    }
    return 0
}

func clearLeftCurve(_ image: CGImage, points: [(Double, Double)]) throws -> CGImage {
    guard !points.isEmpty else { return image }
    var (pixels, width, height, colorSpace) = try imageBuffer(from: image)
    for y in 0..<height {
        let boundary = boundaryX(forY: y, points: points)
        guard boundary > 0 else { continue }
        let hard = max(0, Int(boundary.rounded(.down)) - 10)
        let softEnd = min(width - 1, Int(boundary.rounded(.up)) + 10)
        for x in 0...softEnd {
            let offset = (y * width + x) * 4
            if x <= hard {
                pixels[offset + 3] = 0
            } else {
                let t = Double(x - hard) / Double(max(1, softEnd - hard))
                pixels[offset + 3] = UInt8(Double(pixels[offset + 3]) * t)
            }
        }
    }
    return try makeImage(from: &pixels, width: width, height: height, colorSpace: colorSpace)
}

func trimTransparentBorder(_ image: CGImage) throws -> CGImage {
    let (pixels, width, height, _) = try imageBuffer(from: image)
    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return image
    }

    let padding = 4
    let x = max(0, minX - padding)
    let y = max(0, minY - padding)
    let crop = CGRect(
        x: x,
        y: y,
        width: min(width - x, maxX - minX + 1 + padding * 2),
        height: min(height - y, maxY - minY + 1 + padding * 2)
    )
    guard let trimmed = image.cropping(to: crop) else {
        throw RefineError.makeImage
    }
    return trimmed
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw RefineError.writeFailed(path)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    let options = try parseOptions()
    var image = try cgImage(from: options.input!)
    image = try clearLeftCurve(image, points: options.leftCurve)
    image = try clearDarkLeftEdge(image, width: options.leftClearWidth)
    if options.trim {
        image = try trimTransparentBorder(image)
    }
    try writePNG(image, to: options.output!)
    print(options.output!)
} catch let error as RefineError {
    fputs("\(error.description)\n", stderr)
    if case .usage = error {
        exit(2)
    }
    exit(1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
