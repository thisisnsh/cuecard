import SwiftUI
import UIKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// The images placed in scripts, one file each in the app's own storage on
/// this device. A file is named for what's in it, so the same picture added
/// twice, or brought back in with an import, is only kept once.
///
/// A script holds `[image name]` where the image goes. Files that nothing
/// still places — no script being written, saved note, version or open
/// deck — are deleted at launch.
enum ScriptImages {
    /// The longest side an image is kept at. Plenty for any screen it's read
    /// on, and small enough that a script full of photos still shares easily.
    static let maxPixelSize = 2048

    private static let directory: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("ScriptImages", isDirectory: true)

    private static let cache = NSCache<NSString, UIImage>()

    /// Where an image is kept. Nil for a name that isn't a plain file name.
    static func url(for name: String) -> URL? {
        guard isValidName(name) else { return nil }
        return directory?.appendingPathComponent(name)
    }

    /// Whether `name` could be one of the store's files: letters, digits and
    /// dashes, then an extension, as an `[image …]` tag allows.
    static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9-]+\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    static func contains(_ name: String) -> Bool {
        guard let url = url(for: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func data(named name: String) -> Data? {
        url(for: name).flatMap { try? Data(contentsOf: $0) }
    }

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = url(for: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Keep an image, scaled down to `maxPixelSize` and turned upright, and
    /// return its name. Nil if the data isn't an image or couldn't be kept.
    static func add(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        return add(image)
    }

    static func add(_ image: UIImage) -> String? {
        if let cgImage = image.cgImage, image.imageOrientation == .up,
           max(cgImage.width, cgImage.height) <= maxPixelSize {
            return add(cgImage)
        }
        // Drawn again upright, and smaller if it has to be.
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(1, CGFloat(maxPixelSize) / max(pixels.width, pixels.height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !hasAlpha(image.cgImage)
        let size = CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
        let redrawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage.flatMap(add)
    }

    /// Photos as JPEG; anything with see-through parts as PNG, to keep them.
    private static func add(_ image: CGImage) -> String? {
        let isPNG = hasAlpha(image)
        let type = isPNG ? UTType.png : UTType.jpeg
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        let data = encoded as Data
        let hash = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        let name = "\(hash).\(isPNG ? "png" : "jpg")"
        return write(data, named: name) ? name : nil
    }

    private static func hasAlpha(_ image: CGImage?) -> Bool {
        switch image?.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: return true
        default: return false
        }
    }

    /// Keep `data` as `name`, a file from the notes folder or an older copy of
    /// the store, without changing it. False if the name isn't one the store
    /// uses, or the data isn't an image.
    @discardableResult
    static func add(_ data: Data, named name: String) -> Bool {
        guard isValidName(name), UIImage(data: data) != nil else { return false }
        return write(data, named: name)
    }

    private static func write(_ data: Data, named name: String) -> Bool {
        guard let directory, let url = url(for: name) else { return false }
        if FileManager.default.fileExists(atPath: url.path) { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Delete every image not in `names`. An image added in the last day is
    /// kept whatever, so one placed while this runs is never caught by it.
    static func removeUnused(keeping names: Set<String>) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where !names.contains(file.lastPathComponent) {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard (modified ?? .distantPast) < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
            cache.removeObject(forKey: file.lastPathComponent as NSString)
        }
    }

    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        cache.removeAllObjects()
    }
}

// MARK: - Drawing in text

/// An image placed in a script, as a text view draws it: as wide as the line,
/// no taller than `maxHeight`, with its corners rounded. One that isn't in
/// the store is drawn as an empty frame.
///
/// The editor holds one of these where the script has its `[image …]` tag,
/// and the teleprompter and its floating window draw them too.
final class ScriptImageAttachment: NSTextAttachment {
    let name: String
    let maxHeight: CGFloat
    private var rendered: (size: CGSize, image: UIImage)?

    init(name: String, maxHeight: CGFloat) {
        self.name = name
        self.maxHeight = maxHeight
        super.init(data: nil, ofType: nil)
        // Always drawn as an image, never handed to a view of its own.
        allowsTextAttachmentView = false
    }

    // Text views archive their text now and then, as for a drag.
    required init?(coder: NSCoder) {
        name = coder.decodeObject(of: NSString.self, forKey: "name") as String? ?? ""
        maxHeight = coder.decodeDouble(forKey: "maxHeight")
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(name as NSString, forKey: "name")
        coder.encode(Double(maxHeight), forKey: "maxHeight")
    }

    override class var supportsSecureCoding: Bool { true }

    private var picture: UIImage? { ScriptImages.image(named: name) }

    /// How tall the picture is for its width; a missing one is drawn 4:3.
    private var aspectRatio: CGFloat {
        guard let size = picture?.size, size.width > 0, size.height > 0 else { return 0.75 }
        return size.height / size.width
    }

    /// Lines of reading time the image takes in the teleprompter, so the
    /// script doesn't race past it: more for a tall picture than a wide one.
    var readingLines: Int {
        max(2, min(8, Int((4 * aspectRatio).rounded())))
    }

    /// The size it's drawn at on a line `width` wide.
    func size(forLineWidth width: CGFloat) -> CGSize {
        guard width > 0 else { return .zero }
        var size = CGSize(width: floor(width), height: floor(width * aspectRatio))
        if size.height > maxHeight {
            size = CGSize(width: floor(maxHeight / aspectRatio), height: floor(maxHeight))
        }
        return size
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        CGRect(origin: .zero, size: size(forLineWidth: lineFrag.width))
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        CGRect(origin: .zero, size: size(forLineWidth: proposedLineFragment.width))
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?,
                        characterIndex charIndex: Int) -> UIImage? {
        image(sized: imageBounds.size)
    }

    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                        textContainer: NSTextContainer?) -> UIImage? {
        image(sized: bounds.size)
    }

    /// The picture with its corners rounded, drawn once for each size.
    private func image(sized size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        if let rendered, rendered.size == size { return rendered.image }

        let picture = picture
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let frame = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: frame, cornerRadius: min(12, size.width * 0.04)).addClip()
            if let picture {
                picture.draw(in: frame)
            } else {
                UIColor.gray.withAlphaComponent(0.2).setFill()
                UIRectFill(frame)
                let symbol = UIImage(systemName: "photo", withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: min(size.width, size.height) * 0.2))?
                    .withTintColor(.gray, renderingMode: .alwaysOriginal)
                if let symbol {
                    symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2,
                                            y: (size.height - symbol.size.height) / 2))
                }
            }
        }
        rendered = (size, image)
        return image
    }
}

// MARK: - Drawing in SwiftUI

/// An image placed in a script, fit to the room it's given with its corners
/// rounded. One that isn't in the store is drawn as an empty frame.
struct ScriptImageView: View {
    let name: String
    var cornerRadius: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let image = ScriptImages.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(shape)
                .accessibilityLabel("Image")
        } else {
            shape
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.gray)
                }
                .accessibilityLabel("Image")
        }
    }
}
