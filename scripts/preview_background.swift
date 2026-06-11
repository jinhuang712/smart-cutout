import AppKit

enum PreviewError: Error, CustomStringConvertible {
    case usage
    case loadImage(String)
    case badColor(String)
    case makeImage
    case writeFailed(String)

    var description: String {
        switch self {
        case .usage:
            return usageText
        case .loadImage(let path):
            return "Failed to load image: \(path)"
        case .badColor(let value):
            return "Bad color. Use #RRGGBB: \(value)"
        case .makeImage:
            return "Failed to create image"
        case .writeFailed(let path):
            return "Failed to write output: \(path)"
        }
    }
}

let usageText = """
Usage:
  swift preview_background.swift --input <transparent.png> --output <preview.png> [--color #RRGGBB]
"""

struct Options {
    var input: String?
    var output: String?
    var color = "#8CD2FF"
}

func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        switch args[index] {
        case "--input":
            index += 1
            guard index < args.count else { throw PreviewError.usage }
            options.input = args[index]
        case "--output":
            index += 1
            guard index < args.count else { throw PreviewError.usage }
            options.output = args[index]
        case "--color":
            index += 1
            guard index < args.count else { throw PreviewError.usage }
            options.color = args[index]
        case "--help", "-h":
            print(usageText)
            exit(0)
        default:
            throw PreviewError.usage
        }
        index += 1
    }
    guard options.input != nil, options.output != nil else {
        throw PreviewError.usage
    }
    return options
}

func parseColor(_ value: String) throws -> CGColor {
    let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6, let rgb = UInt32(cleaned, radix: 16) else {
        throw PreviewError.badColor(value)
    }
    let r = CGFloat((rgb >> 16) & 0xff) / 255.0
    let g = CGFloat((rgb >> 8) & 0xff) / 255.0
    let b = CGFloat(rgb & 0xff) / 255.0
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

func cgImage(from path: String) throws -> CGImage {
    guard let source = NSImage(contentsOfFile: path),
          let tiff = source.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let image = bitmap.cgImage else {
        throw PreviewError.loadImage(path)
    }
    return image
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw PreviewError.writeFailed(path)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    let options = try parseOptions()
    let image = try cgImage(from: options.input!)
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw PreviewError.makeImage
    }
    context.setFillColor(try parseColor(options.color))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let preview = context.makeImage() else {
        throw PreviewError.makeImage
    }
    try writePNG(preview, to: options.output!)
    print(options.output!)
} catch let error as PreviewError {
    fputs("\(error.description)\n", stderr)
    if case .usage = error {
        exit(2)
    }
    exit(1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
