//
//  TukView.swift
//  LIFTR
//

import SwiftUI
import UIKit
import WebKit

/// Tuk, animated. The rig is the design's own SVG (`Resources/Tuk/tuk.html`), shown in a
/// transparent web view so the hand-drawn line boil and every stage animation come across as
/// designed. A still image stands in while it loads, and whenever Reduce Motion is on.
struct TukView: View {
    enum Mode: String {
        /// The stage's idle animation, like the smoking loop at stage 1.
        case loop
        /// Slow in-and-out breathing that matches the craving help exercise.
        case breathe
    }

    var stage: TukStage
    var mode: Mode = .loop
    /// Draws Tuk's little world (sky, hills, sun) behind him, as on Home.
    var showsScene = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            if showsScene {
                stage.skyColor
            } else {
                stage.image
                    .resizable()
                    .scaledToFit()
                    .opacity(isLoaded && !reduceMotion ? 0 : 1)
            }
            if !reduceMotion || showsScene {
                TukWebView(stage: stage, mode: mode, showsScene: showsScene) { isLoaded = true }
                    .opacity(isLoaded ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isLoaded)
        .accessibilityElement()
        .accessibilityLabel("Tuk the tortoise, \(stage.title.lowercased())")
    }
}

/// Tuk's head in a round frame, for avatars next to messages.
struct TukAvatar: View {
    var stage: TukStage
    var size: CGFloat = 44
    var lineWidth: CGFloat = 1.5

    var body: some View {
        stage.headImage
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Palette.avatar)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Palette.outline, lineWidth: lineWidth))
            .accessibilityHidden(true)
    }
}

private struct TukWebView: UIViewRepresentable {
    var stage: TukStage
    var mode: TukView.Mode
    var showsScene: Bool
    var onLoad: () -> Void

    static let pageURL = Bundle.main.url(forResource: "tuk", withExtension: "html")
        ?? Bundle.main.url(forResource: "tuk", withExtension: "html", subdirectory: "Resources/Tuk")

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.startScript(stage: stage, mode: mode, showsScene: showsScene), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Taps go to the SwiftUI view underneath (for example, poking Tuk on Home).
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.stage = stage
        context.coordinator.mode = mode
        context.coordinator.onLoad = onLoad
        if let url = Self.pageURL {
            webView.loadFileURL(url, allowingReadAccessTo: Bundle.main.bundleURL)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoad = onLoad
        context.coordinator.show(stage: stage, mode: mode, in: webView)
    }

    /// Sets the page's parameters before it runs, and points it at the bundled hand-drawn font.
    private static func startScript(stage: TukStage, mode: TukView.Mode, showsScene: Bool) -> String {
        var script = "window.TUK_PARAMS = {stage: \(stage.rawValue), mode: '\(mode.rawValue)', scene: \(showsScene ? "'home'" : "null")};"
        if let font = Bundle.main.url(forResource: "PatrickHand-Regular", withExtension: "ttf") {
            script += """
            (function () {
              var style = document.createElement('style');
              style.textContent = "@font-face{font-family:'Patrick Hand';src:url('\(font.absoluteString)') format('truetype')}";
              document.documentElement.appendChild(style);
            })();
            """
        }
        return script
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var stage = TukStage.cuttingDown
        var mode = TukView.Mode.loop
        var onLoad: () -> Void = {}
        private var isLoaded = false

        /// Changes the stage in place so the rig's transitions play (smoke fades, sprouts grow).
        func show(stage: TukStage, mode: TukView.Mode, in webView: WKWebView) {
            guard stage != self.stage || mode != self.mode else { return }
            self.stage = stage
            self.mode = mode
            if isLoaded { push(to: webView) }
        }

        private func push(to webView: WKWebView) {
            webView.evaluateJavaScript("window.tuk && window.tuk.set({stage: \(stage.rawValue), mode: '\(mode.rawValue)'})")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            // The stage may have changed while the page was loading.
            push(to: webView)
            onLoad()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isLoaded = false
            webView.reload()
        }
    }
}
