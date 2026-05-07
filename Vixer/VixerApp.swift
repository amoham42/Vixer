import AppKit
import SwiftUI

@main
struct VixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct MixerStatusPresentation {
    static let cornerRadius: CGFloat = 7
    static let borderOpacity: CGFloat = 0.22
    static let verticalOffset: CGFloat = 6
    static let screenEdgePadding: CGFloat = 10
}

final class MixerStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusPanel: MixerStatusPanel?
    private var outsideClickMonitor: Any?
    private let mixerPresentationState = MixerPresentationState()
    private var currentContentSize = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 3, canExpand: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = VixerIcon.templateImage(size: NSSize(width: 18, height: 18))
                ?? NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Vixer")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(toggleStatusPanel(_:))
        }
        statusItem = item

        createStatusPanel()

    }

    @objc private func toggleStatusPanel(_ sender: Any?) {
        guard let panel = statusPanel, let button = statusItem?.button else { return }
        if panel.isVisible {
            closeStatusPanel()
        } else {
            mixerPresentationState.resetForNewPresentation()
            currentContentSize = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 3, canExpand: true)
            setStatusPanelSize(currentContentSize)
            positionStatusPanel(relativeTo: button)
            panel.orderFrontRegardless()
            panel.makeKey()
            installOutsideClickMonitor()
        }
    }

    private func createStatusPanel() {
        let panel = MixerStatusPanel(
            contentRect: NSRect(origin: .zero, size: currentContentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let rootView = MixerView(presentationState: mixerPresentationState) { [weak self] size in
            self?.currentContentSize = size
            self?.setStatusPanelSize(size)
            if let button = self?.statusItem?.button {
                self?.positionStatusPanel(relativeTo: button)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: MixerStatusPresentation.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MixerStatusPresentation.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(MixerStatusPresentation.borderOpacity), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MixerStatusPresentation.cornerRadius, style: .continuous))

        panel.contentViewController = NSHostingController(rootView: rootView)
        statusPanel = panel
    }

    private func setStatusPanelSize(_ size: CGSize) {
        statusPanel?.setContentSize(size)
    }

    private func positionStatusPanel(relativeTo button: NSStatusBarButton) {
        guard let panel = statusPanel, let buttonWindow = button.window else { return }
        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let unclampedX = buttonFrameInScreen.midX - currentContentSize.width / 2
        let minX = screenFrame.minX + MixerStatusPresentation.screenEdgePadding
        let maxX = screenFrame.maxX - currentContentSize.width - MixerStatusPresentation.screenEdgePadding
        let origin = NSPoint(
            x: min(max(unclampedX, minX), maxX),
            y: buttonFrameInScreen.minY - currentContentSize.height - MixerStatusPresentation.verticalOffset
        )
        panel.setFrameOrigin(origin)
    }

    private func installOutsideClickMonitor() {
        if outsideClickMonitor != nil { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.statusPanel, panel.isVisible else { return }
            if !panel.frame.contains(event.locationInWindow) {
                self.closeStatusPanel()
            }
        }
    }

    private func closeStatusPanel() {
        statusPanel?.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
