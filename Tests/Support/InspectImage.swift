import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: inspect-image <image-path>\n", stderr)
    exit(EXIT_FAILURE)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Could not decode image: \(imageURL.path)\n", stderr)
    exit(EXIT_FAILURE)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
        let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard rendered else {
    fputs("Could not render image pixels.\n", stderr)
    exit(EXIT_FAILURE)
}

var opaqueCount = 0
var minimumX = width
var minimumY = height
var maximumX = -1
var maximumY = -1
for y in 0..<height {
    for x in 0..<width {
        let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
        guard alpha >= 250 else { continue }
        opaqueCount += 1
        minimumX = min(minimumX, x)
        minimumY = min(minimumY, y)
        maximumX = max(maximumX, x)
        maximumY = max(maximumY, y)
    }
}

guard opaqueCount > 0 else {
    fputs("Image has no opaque pixels.\n", stderr)
    exit(EXIT_FAILURE)
}

let opaqueWidth = maximumX - minimumX + 1
let opaqueHeight = maximumY - minimumY + 1
let opaqueFraction = Double(opaqueCount) / Double(width * height)
let widthCoverage = Double(opaqueWidth) / Double(width)
let heightCoverage = Double(opaqueHeight) / Double(height)

print("width=\(width)")
print("height=\(height)")
print("opaque_fraction=\(String(format: "%.6f", opaqueFraction))")
print("opaque_width_coverage=\(String(format: "%.6f", widthCoverage))")
print("opaque_height_coverage=\(String(format: "%.6f", heightCoverage))")
