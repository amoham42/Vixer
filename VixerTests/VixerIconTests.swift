import AppKit
import Testing
@testable import Vixer

@MainActor
struct VixerIconTests {
    @Test func templateIconLoadsAndAdaptsToCurrentAppearance() {
        let image = VixerIcon.templateImage()

        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }

    @Test func appBundleDeclaresAssetCatalogAppIcon() {
        #expect(VixerIcon.bundleIconName(in: .main) == "AppIcon")
    }

    @Test func showMoreIconLoadsAsTemplateSVGAsset() {
        let image = VixerIcon.templateImage(named: VixerIcon.showMoreAssetName)

        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }

    @Test func showLessIconLoadsAsTemplateSVGAsset() {
        let image = VixerIcon.templateImage(named: VixerIcon.showLessAssetName)

        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }

    @Test func iconMetricsKeepMasterFrameConsistentWithAppIcons() {
        #expect(MixerIconMetrics.masterFrameSize == MixerIconMetrics.appFrameSize)
        #expect(MixerIconMetrics.masterGlyphSize.width <= MixerIconMetrics.appFrameSize.width)
        #expect(MixerIconMetrics.masterGlyphSize.height <= MixerIconMetrics.appFrameSize.height)
    }

    @Test func expansionIconMetricsKeepArtworkInsideButtonFrame() {
        #expect(MixerIconMetrics.showMoreIconSize.width <= MixerIconMetrics.expansionIconFrameSize.width)
        #expect(MixerIconMetrics.showMoreIconSize.height <= MixerIconMetrics.expansionIconFrameSize.height)
        #expect(MixerIconMetrics.showLessIconSize.width <= MixerIconMetrics.expansionIconFrameSize.width)
        #expect(MixerIconMetrics.showLessIconSize.height <= MixerIconMetrics.expansionIconFrameSize.height)
    }

    @Test func expansionSVGArtworkUsesRoundedTopCardCorners() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let assetRoot = projectRoot.appendingPathComponent("Vixer/Assets.xcassets")
        let showMoreSVG = try String(contentsOf: assetRoot.appendingPathComponent("VixerShowMoreIcon.imageset/vixer-show-more.svg"))
        let showLessSVG = try String(contentsOf: assetRoot.appendingPathComponent("VixerShowLessIcon.imageset/vixer-show-less.svg"))

        #expect(showMoreSVG.contains("rx=\"64\" ry=\"64\""))
        #expect(showLessSVG.contains("rx=\"64\" ry=\"64\""))
    }
}
