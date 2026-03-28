import SwiftUI
import AppKit

@main
struct ClimateLiberatorApp: App {
    @StateObject private var scenarioStore = ScenarioLibraryStore()
    @StateObject private var reviewStore = TCFDReviewStore()
    @StateObject private var forecastStore = ForecastIntelligenceStore()

    var body: some Scene {
        WindowGroup {
            LaunchExperienceView {
                ContentView(scenarioStore: scenarioStore, reviewStore: reviewStore, forecastStore: forecastStore)
            }
            .background(MainWindowFullscreenEnforcer())
        }

        Window("TCFD Dashboard", id: "tcfd-dashboard") {
            TCFDDashboardScreen(scenarioStore: scenarioStore, reviewStore: reviewStore, forecastStore: forecastStore)
        }

        Window("Forecast Intelligence", id: "forecast-intelligence") {
            ForecastIntelligenceWindow(store: forecastStore)
        }
        .commands {
            CommandGroup(after: .appTermination) {
                Button("Quit Climate Liberator") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

private struct MainWindowFullscreenEnforcer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.ensureFullscreen(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.ensureFullscreen(for: nsView)
        }
    }

    final class Coordinator {
        private var appliedWindowNumber: Int?

        func ensureFullscreen(for view: NSView) {
            guard let window = view.window else { return }
            guard appliedWindowNumber != window.windowNumber else { return }

            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenAllowsTiling)
            appliedWindowNumber = window.windowNumber

            guard !window.styleMask.contains(.fullScreen) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    }
}

private struct LaunchExperienceView<Content: View>: View {
    private let content: Content

    @State private var didStartAnimation = false
    @State private var iconScale: CGFloat = 0.86
    @State private var iconOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var titleOffset: CGFloat = 16
    @State private var glowScale: CGFloat = 0.84
    @State private var splashOpacity = 1.0
    @State private var splashVisible = true

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .opacity(splashVisible ? 0.0 : 1.0)

            if splashVisible {
                splashLayer
                    .transition(.opacity)
            }
        }
        .onAppear(perform: startAnimationIfNeeded)
    }

    private var splashLayer: some View {
        ZStack {
            Image("LaunchMark")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.06),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
            .scaleEffect(glowScale)
            .blur(radius: 20)

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.56),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 8) {
                    Text("Climate Liberator")
                        .font(.custom("Avenir Next", size: 40))
                        .fontWeight(.medium)
                        .tracking(0.4)
                        .foregroundStyle(.white)
                    Text("Climate Risk Intelligence")
                        .font(.custom("Avenir Next", size: 20))
                        .fontWeight(.regular)
                        .tracking(0.2)
                        .foregroundStyle(Color.white.opacity(0.90))
                }
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.55), radius: 14, y: 5)
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                .padding(.bottom, 92)
            }
        }
        .opacity(splashOpacity)
        .ignoresSafeArea()
    }

    private func startAnimationIfNeeded() {
        guard !didStartAnimation else { return }
        didStartAnimation = true

        withAnimation(.spring(response: 0.82, dampingFraction: 0.8)) {
            iconScale = 1.0
            iconOpacity = 1.0
            glowScale = 1.08
        }

        withAnimation(.easeOut(duration: 0.55).delay(0.12)) {
            titleOpacity = 1.0
            titleOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.65) {
            withAnimation(.easeInOut(duration: 0.32)) {
                splashOpacity = 0.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            splashVisible = false
        }
    }
}
