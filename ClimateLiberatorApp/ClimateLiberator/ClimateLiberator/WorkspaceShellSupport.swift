import SwiftUI

extension View {
    func glassBackground(material: Material,
                         tint: Color,
                         cornerRadius: CGFloat,
                         strokeColor: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
        )
    }
}
