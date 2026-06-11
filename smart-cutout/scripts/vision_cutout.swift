import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum CutoutError: Error, CustomStringConvertible {
    case usage
    case loadImage(String)
    case cropOutOfBounds(String)
    case makeImage
    case noObservation
    case noInstances
    case writeFailed(String)

    var description: String {
        switch self {
        case .usage:
            return usageText
        case .loadImage(let path):
            return "Failed to load image: \(path)"
        case .cropOutOfBounds(let value):
            return "Crop is outside image bounds: \(value)"
        case .makeImage:
            return "Failed to create image"
        case .noObservation:
            return "Vision did not return a foreground mask"
        case .noInstances:
            return "Vision did not find a foreground instance"
        case .writeFailed(let path):
            return "Failed to write output: \(path)"
        }
    }
}

let usageText = """
Usage:
  swift vision_cutout.swift --input <image> --output <png> [options]

Options:
  --crop x,y,w,h       Pixel crop before segmentation.
  --crop-frac x,y,w,h  Fractional crop before segmentation, each value 0..1.
  --all-instances      Keep all foreground instances instead of the largest.
"""

struct Options {
    var input: String?
    var output: String?
    var cropPixels: CGRect?
    var cropFrac: CGRect?
    var keepAllInstances = false
}

func parseRect(_ value: String) throws -> CGRect {
    let parts = value.split(separator: ",").map(String.init)
    guard parts.count == 4,
          let x = Double(parts[0]),
          let y = Double(parts[1]),
          let w = Double(parts[2]),
          let h = Double(parts[3]) else {
        throw CutoutError.cropOutOfBounds(value)
    }
    return CGRect(x: x, y: y, width: w, height: h)
}

func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--input":
            index += 1
            guard index < args.count else { throw CutoutError.usage }
            options.input = args[index]
        case "--output":
            index += 1
            guard index < args.count else { throw CutoutError.usage }
            options.output = args[index]
        case "--crop":
            index += 1
            guard index < args.count else { throw CutoutError.usage }
            options.cropPixels = try parseRect(args[index])
        case "--crop-frac":
            index += 1
            guard index < args.count else { throw CutoutError.usage }
            options.cropFrac = try parseRect(args[index])
        case "--all-instances":
            options.keepAllInstances = true
        case "--help", "-h":
            print(usageText)
            exit(0)
        default:
            throw CutoutError.usage
        }
        index += 1
    }
    guard options.input != nil, options.output != nil else {
        throw CutoutError.usage
    }
    return options
}

func cgImage(from path: String) throws -> CGImage {
    guard let source = NSImage(contentsOfFile: path),
          let tiff = source.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let image = bitmap.cgImage else {
        throw CutoutError.loadImage(path)
    }
    return image
}

func cropRect(for image: CGImage, options: Options) throws -> CGRect {
    let width = Double(image.width)
    let height = Double(image.height)
    let rect: CGRect
    if let cropFrac = options.cropFrac {
        rect = CGRect(
            x: cropFrac.minX * width,
            y: cropFrac.minY * height,
            width: cropFrac.width * width,
            height: cropFrac.height * height
        )
    } else if let cropPixels = options.cropPixels {
        rect = cropPixels
    } else {
        rect = CGRect(x: 0, y: 0, width: width, height: height)
    }

    let integral = rect.integral
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    guard bounds.contains(integral), integral.width > 0, integral.height > 0 else {
        throw CutoutError.cropOutOfBounds("\(rect)")
    }
    return integral
}

func countOpaquePixels(in mask: CVPixelBuffer) -> Int {
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    let width = CVPixelBufferGetWidth(mask)
    let height = CVPixelBufferGetHeight(mask)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
    guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) else {
        return 0
    }
    var count = 0
    for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow)
        for x in 0..<width where row[x] > 20 {
            count += 1
        }
    }
    return count
}

func alphaComposite(cropped: CGImage, maskBuffer: CVPixelBuffer) throws -> CGImage {
    let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    let croppedCI = CIImage(cgImage: cropped)
    var maskCI = CIImage(cvPixelBuffer: maskBuffer)
    let scaleX = croppedCI.extent.width / maskCI.extent.width
    let scaleY = croppedCI.extent.height / maskCI.extent.height
    maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    let transparent = CIImage(color: .clear).cropped(to: croppedCI.extent)
    let blend = CIFilter.blendWithMask()
    blend.inputImage = croppedCI
    blend.backgroundImage = transparent
    blend.maskImage = maskCI

    guard let output = blend.outputImage,
          let image = ciContext.createCGImage(output, from: croppedCI.extent) else {
        throw CutoutError.makeImage
    }
    return image
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CutoutError.writeFailed(path)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    let options = try parseOptions()
    let source = try cgImage(from: options.input!)
    let rect = try cropRect(for: source, options: options)
    guard let cropped = source.cropping(to: rect) else {
        throw CutoutError.makeImage
    }

    let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])

    guard let observation = request.results?.first else {
        throw CutoutError.noObservation
    }
    let instances = observation.allInstances
    guard !instances.isEmpty else {
        throw CutoutError.noInstances
    }

    let selectedInstances: IndexSet
    if options.keepAllInstances || instances.count == 1 {
        selectedInstances = instances
    } else {
        var bestInstance = instances.first!
        var bestCount = -1
        for instance in instances {
            let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
            let count = countOpaquePixels(in: mask)
            if count > bestCount {
                bestCount = count
                bestInstance = instance
            }
        }
        selectedInstances = IndexSet(integer: bestInstance)
    }

    let mask = try observation.generateScaledMaskForImage(forInstances: selectedInstances, from: handler)
    let output = try alphaComposite(cropped: cropped, maskBuffer: mask)
    try writePNG(output, to: options.output!)
    print(options.output!)
} catch let error as CutoutError {
    fputs("\(error.description)\n", stderr)
    if case .usage = error {
        exit(2)
    }
    exit(1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
