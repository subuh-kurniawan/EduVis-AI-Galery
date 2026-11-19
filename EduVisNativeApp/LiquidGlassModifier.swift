//
//  LiquidGlassModifier.swift
//  EduVis Native AI
//
//  Gaya visual Liquid Glass standar resmi Apple Developer HIG:
//  Material ultra-thin/thin, geometri konsentris (.continuous), 3-point specular bevel, dan kedalaman adaptif.
//

import SwiftUI
import AppKit

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var strokeOpacity: Double = 0.22
    var tintColor: Color? = nil
    var shadowRadius: CGFloat = 10
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let topRim = isDark ? Color(red: 0.96, green: 0.50, blue: 0.80).opacity(min(strokeOpacity * 1.45, 0.45)) : Color.white.opacity(min(strokeOpacity * 3.2, 0.85))
        let midRim = isDark ? Color(red: 0.65, green: 0.45, blue: 0.98).opacity(strokeOpacity * 0.65) : Color.white.opacity(0.32)
        let bottomRim = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08)

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tintColor {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tintColor.opacity(isDark ? 0.14 : 0.09))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [topRim, midRim, bottomRim],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(isDark ? 0.22 : 0.08), radius: shadowRadius, x: 0, y: 4)
            }
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tintColor: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let topRim = isDark ? Color.white.opacity(0.26) : Color.white.opacity(0.88)
        let midRim = isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.36)
        let bottomRim = isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.09)

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        if let tintColor {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tintColor.opacity(isDark ? 0.12 : 0.08))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [topRim, midRim, bottomRim],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(isDark ? 0.28 : 0.10), radius: 14, x: 0, y: 6)
            }
    }
}

struct LiquidGlassBarModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        isDark ? Color.white.opacity(0.30) : Color.white.opacity(0.92),
                                        isDark ? Color.white.opacity(0.11) : Color.white.opacity(0.38),
                                        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.08),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(isDark ? 0.22 : 0.10), radius: 14, x: 0, y: 5)
            }
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        strokeOpacity: Double = 0.22,
        tint: Color? = nil,
        shadowRadius: CGFloat = 10
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            strokeOpacity: strokeOpacity,
            tintColor: tint,
            shadowRadius: shadowRadius
        ))
    }

    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            tintColor: tint
        ))
    }

    func liquidGlassBar() -> some View {
        modifier(LiquidGlassBarModifier())
    }
}
