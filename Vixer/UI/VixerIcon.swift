import AppKit

struct MixerIconMetrics {
    static let appFrameSize = NSSize(width: 24, height: 24)
    static let masterFrameSize = appFrameSize
    static let masterGlyphSize = NSSize(width: 20, height: 20)

    /// Visual size for the collapsed-state expander icon. Decrease/increase this
    /// to make the show-more icon smaller/larger.
    static let showMoreIconSize = NSSize(width: 15, height: 15)

    /// Visual size for the expanded-state expander icon. Decrease/increase this
    /// to make the show-less icon smaller/larger.
    static let showLessIconSize = NSSize(width: 15, height: 15)

    /// Hit target / layout box for the expander button. Usually leave this larger
    /// than the artwork sizes so the button remains easy to click.
    static let expansionIconFrameSize = NSSize(width: 18, height: 18)
}

enum VixerIcon {
    static let templateAssetName = "VixerTemplateIcon"
    static let showMoreAssetName = "VixerShowMoreIcon"
    static let showLessAssetName = "VixerShowLessIcon"

    static func templateImage(size: NSSize? = nil) -> NSImage? {
        templateImage(named: templateAssetName, size: size)
    }

    static func templateImage(named assetName: String, size: NSSize? = nil) -> NSImage? {
        guard let image = NSImage(named: assetName)?.copy() as? NSImage else {
            return nil
        }
        image.isTemplate = true
        if let size {
            image.size = size
        }
        return image
    }
}
