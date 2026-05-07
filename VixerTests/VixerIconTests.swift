import AppKit
import XCTest
@testable import Vixer

final class VixerIconTests: XCTestCase {
    func test_templateIcon_loadsAndAdaptsToCurrentAppearance() {
        let image = VixerIcon.templateImage()

        XCTAssertNotNil(image)
        XCTAssertTrue(image?.isTemplate == true)
    }

    func test_appBundle_declaresAssetCatalogAppIcon() {
        XCTAssertEqual(VixerIcon.bundleIconName(in: .main), "AppIcon")
    }

    func test_showMoreIcon_loadsAsTemplateSVGAsset() {
        let image = VixerIcon.templateImage(named: VixerIcon.showMoreAssetName)

        XCTAssertNotNil(image)
        XCTAssertTrue(image?.isTemplate == true)
    }

    func test_showLessIcon_loadsAsTemplateSVGAsset() {
        let image = VixerIcon.templateImage(named: VixerIcon.showLessAssetName)

        XCTAssertNotNil(image)
        XCTAssertTrue(image?.isTemplate == true)
    }

    func test_iconMetrics_keepMasterFrameConsistentWithAppIcons() {
        XCTAssertEqual(MixerIconMetrics.masterFrameSize, MixerIconMetrics.appFrameSize)
        XCTAssertLessThanOrEqual(MixerIconMetrics.masterGlyphSize.width, MixerIconMetrics.appFrameSize.width)
        XCTAssertLessThanOrEqual(MixerIconMetrics.masterGlyphSize.height, MixerIconMetrics.appFrameSize.height)
    }

    func test_expansionIconMetrics_keepArtworkInsideButtonFrame() {
        XCTAssertLessThanOrEqual(MixerIconMetrics.showMoreIconSize.width, MixerIconMetrics.expansionIconFrameSize.width)
        XCTAssertLessThanOrEqual(MixerIconMetrics.showMoreIconSize.height, MixerIconMetrics.expansionIconFrameSize.height)
        XCTAssertLessThanOrEqual(MixerIconMetrics.showLessIconSize.width, MixerIconMetrics.expansionIconFrameSize.width)
        XCTAssertLessThanOrEqual(MixerIconMetrics.showLessIconSize.height, MixerIconMetrics.expansionIconFrameSize.height)
    }

    func test_expansionSVGArtwork_usesRoundedTopCardCorners() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let assetRoot = projectRoot.appendingPathComponent("Vixer/Assets.xcassets")
        let showMoreSVG = try String(contentsOf: assetRoot.appendingPathComponent("VixerShowMoreIcon.imageset/vixer-show-more.svg"))
        let showLessSVG = try String(contentsOf: assetRoot.appendingPathComponent("VixerShowLessIcon.imageset/vixer-show-less.svg"))

        XCTAssertTrue(showMoreSVG.contains("rx=\"64\" ry=\"64\""))
        XCTAssertTrue(showLessSVG.contains("rx=\"64\" ry=\"64\""))
    }
}
