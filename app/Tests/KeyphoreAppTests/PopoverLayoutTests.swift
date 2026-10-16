import AppKit
import KeyphoreCore
import SwiftUI
import XCTest

@MainActor
final class PopoverLayoutTests: XCTestCase {
    func testMulticolorModeKeepsNativeColorControlsVisible() throws {
        let appearance = ZoneAppearance(
            effect: .backlightBreathing,
            color: SignalColor(red: 0, green: 149, blue: 255),
            colorMode: .multicolor
        )
        let hosting = NSHostingController(rootView: NativeColorPanel(
            appearance: appearance, reset: {}, updateColorMode: { _ in }, updateColor: { _ in }
        ))
        let fitted = hosting.sizeThatFits(in: NSSize(width: 430, height: 600))
        XCTAssertGreaterThan(fitted.height, 250, "Multicolor mode must retain presets and the custom picker")
        hosting.view.frame = NSRect(origin: .zero, size: NSSize(width: 430, height: fitted.height))
        hosting.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.view.bitmapImageRepForCachingDisplay(in: hosting.view.bounds))
        hosting.view.cacheDisplay(in: hosting.view.bounds, to: bitmap)
        let containsOfficialOrange = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return abs(color.redComponent * 255 - 255) < 2
                    && abs(color.greenComponent * 255 - 109) < 2
                    && abs(color.blueComponent * 255 - 30) < 2
            }
        }
        XCTAssertTrue(containsOfficialOrange, "The official color presets must remain visible")
    }

    func testHostedNativeKeyboardPreviewDoesNotInventPerKeyAnimation() throws {
        for controls: ControlActiveState in [.key, .inactive] {
            // Render the production preview itself, excluding unrelated settings controls and layout.
            let hosting = NSHostingController(rootView: Air65KeyboardView(presentation: KeyboardSignalPresentation(
                signal: .execution, appearance: LocalProfile.default.execution, controlledZones: .backlight
            ), layout: .air75ANSI)
                .frame(width: 180, height: 82)
                .environment(\.scenePhase, .background)
                .environment(\.controlActiveState, controls))
            let window = NSWindow(contentViewController: hosting)
            window.setContentSize(NSSize(width: 180, height: 82))
            var frames = Set<Data>()
            for _ in 0..<4 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                hosting.view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.view.bitmapImageRepForCachingDisplay(in: hosting.view.bounds))
                hosting.view.cacheDisplay(in: hosting.view.bounds, to: bitmap)
                frames.insert(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
            }
            XCTAssertEqual(frames.count, 1, "controls=\(controls)")
        }
    }

    func testDisconnectedKeyboardUsesGenericPresentation() {
        let state = KeyphoreAppState(environment: ["KEYPHORE_ACCEPTANCE_FIXTURE": "configured"])
        let popover = KeyphorePopover(state: state)

        XCTAssertTrue(popover.usesGenericKeyboardPresentation)
    }

    func testLocalizedPanelsFitTheirWidthAndAttachPreviews() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        for choice in AppLanguageChoice.allCases where choice != .system {
            var arguments = previous
            arguments["app.language"] = choice.rawValue
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let state = KeyphoreAppState(environment: ["KEYPHORE_ACCEPTANCE_FIXTURE": "ready-attention"])
            let popover = NSHostingController(rootView: KeyphorePopover(state: state))
            let size = popover.sizeThatFits(in: NSSize(width: 392, height: 0))
            XCTAssertEqual(size.width, 392, accuracy: 1)
            XCTAssertGreaterThanOrEqual(size.height, 350)
            XCTAssertLessThanOrEqual(size.height, 470, "\(choice)")
            attach(popover.view, size: size, name: "\(choice)-panel")
            for tab in [SettingsTab.lights, .general, .about] {
                state.selectedSettingsTab = tab
                let settings = NSHostingController(rootView: SignalSettingsView(state: state, checkForUpdates: {}))
                let fitted = settings.sizeThatFits(in: NSSize(width: 1040, height: 760))
                XCTAssertEqual(fitted.width, 1040, accuracy: 1)
                attach(settings.view, size: NSSize(width: 1040, height: 760), name: "\(choice)-\(tab)")
                if choice == .simplifiedChinese && tab == .lights {
                    for scheme in [ColorScheme.light, .dark] {
                        let themed = NSHostingController(rootView: SignalSettingsView(state: state, checkForUpdates: {})
                            .environment(\.colorScheme, scheme))
                        themed.view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                        attach(themed.view, size: NSSize(width: 1040, height: 760), name: "color-layout-\(scheme)")
                    }
                }
            }
        }
    }

    private func attach(_ view: NSView, size: NSSize, name: String) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("Could not render \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPopoverMapsEveryAppAppearanceToAColorScheme() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
    }

    func testMenuBarPanelRetainsKeyboardSpaceUnderCompressedHeightProposal() {
        for fixture in ["ready-execution", "ready-attention", "ready-completion", "configured", "ready-off"] {
            let state = KeyphoreAppState(environment: ["KEYPHORE_ACCEPTANCE_FIXTURE": fixture])
            let hosting = NSHostingController(rootView: KeyphorePopover(state: state))

            let size = hosting.sizeThatFits(in: NSSize(width: 392, height: 0))

            XCTAssertEqual(size.width, 392, accuracy: 1)
            XCTAssertGreaterThanOrEqual(size.height, 350, "The approved panel must reserve its 344 × 132 keyboard even during intrinsic sizing: \(fixture)")
            XCTAssertLessThanOrEqual(size.height, 370, "The approved status-first panel has no management footer: \(fixture)")
        }
    }
}
