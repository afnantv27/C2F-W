import SwiftUI

struct ClimateSimulationWorkspaceView: View {
    let theme: ThemeStyle
    let isPanelVisible: Bool
    let controlsExpanded: Bool
    let mapLayer: AnyView
    let searchCard: AnyView
    let earthEngineCard: AnyView
    let themePicker: AnyView
    let siteContent: AnyView
    let inputsContent: AnyView
    let runContent: AnyView
    let outputsContent: AnyView
    let logsContent: AnyView
    let onTogglePanel: () -> Void
    let onToggleExpanded: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            mapLayer
            panelLayer
        }
    }

    private var operationsConsole: some View {
        OperationsWorkspaceView(
            style: WorkspaceSectionStyle(
                textColor: theme.textColor,
                subtleTextColor: theme.subtleTextColor,
                material: theme.material,
                cardTint: theme.cardBackground,
                panelTint: theme.editorBackground,
                borderColor: theme.borderColor,
                shadowColor: theme.shadowColor
            ),
            controlsExpanded: controlsExpanded,
            onToggleExpanded: onToggleExpanded
        ) {
            themePicker
        } siteContent: {
            siteContent
        } inputsContent: {
            inputsContent
        } runContent: {
            runContent
        } outputsContent: {
            outputsContent
        } logsContent: {
            logsContent
        }
    }

    private var panelLayer: some View {
        Group {
            if isPanelVisible {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button(action: onTogglePanel) {
                            Label("Hide Panel", systemImage: "sidebar.leading")
                                .labelStyle(.titleAndIcon)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Spacer()
                    }
                    searchCard
                    earthEngineCard
                    ScrollView {
                        operationsConsole
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 84)
                .padding(.bottom, 32)
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                VStack {
                    HStack {
                        Button(action: onTogglePanel) {
                            Label("Show Panel", systemImage: "sidebar.trailing")
                                .labelStyle(.titleAndIcon)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.leading, 20)
                        .padding(.top, 84)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}
