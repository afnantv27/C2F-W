import SwiftUI

struct WorkspaceSectionStyle {
    let textColor: Color
    let subtleTextColor: Color
    let material: Material
    let cardTint: Color
    let panelTint: Color
    let borderColor: Color
    let shadowColor: Color
}

struct WorkspaceSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let style: WorkspaceSectionStyle
    let content: Content

    init(title: String,
         subtitle: String,
         style: WorkspaceSectionStyle,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(style.textColor)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(style.subtleTextColor)
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(style.material)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(style.panelTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(style.borderColor.opacity(0.85), lineWidth: 1)
                )
        )
    }
}
