//
//  AppColors.swift
//  ShareCore
//
//  Created by Zander Wang on 2025/10/19.
//

import SwiftUI

public enum AppColors {
    private static let background = AdaptiveColor(
        light: Color(red: 246 / 255, green: 246 / 255, blue: 250 / 255),
        dark: Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255)
    )
    private static let cardBackground = AdaptiveColor(
        light: Color.white,
        dark: Color(red: 30 / 255, green: 30 / 255, blue: 36 / 255)
    )
    private static let inputBackground = AdaptiveColor(
        light: Color.white,
        dark: Color(red: 38 / 255, green: 38 / 255, blue: 44 / 255)
    )
    private static let accent = AdaptiveColor(
        light: Color(red: 82 / 255, green: 121 / 255, blue: 248 / 255),
        dark: Color(red: 90 / 255, green: 132 / 255, blue: 255 / 255)
    )
    private static let textPrimary = AdaptiveColor(
        light: Color(red: 28 / 255, green: 28 / 255, blue: 34 / 255),
        dark: Color.white
    )
    private static let textSecondary = AdaptiveColor(
        light: Color.black.opacity(0.6),
        dark: Color.white.opacity(0.65)
    )
    private static let chipPrimaryBackground = AdaptiveColor(
        light: Color(red: 82 / 255, green: 121 / 255, blue: 248 / 255),
        dark: Color(red: 76 / 255, green: 118 / 255, blue: 255 / 255)
    )
    private static let chipSecondaryBackground = AdaptiveColor(
        light: Color.black.opacity(0.05),
        dark: Color.white.opacity(0.25)
    )
    private static let chipPrimaryText = AdaptiveColor(
        light: Color.white,
        dark: Color.white
    )
    private static let chipSecondaryText = AdaptiveColor(
        light: Color.black.opacity(0.7),
        dark: Color.white
    )
    private static let divider = AdaptiveColor(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.08)
    )
    private static let skeleton = AdaptiveColor(
        light: Color.black.opacity(0.08),
        dark: Color.white.opacity(0.12)
    )
    private static let success = AdaptiveColor(
        light: Color(red: 42 / 255, green: 160 / 255, blue: 90 / 255),
        dark: Color(red: 64 / 255, green: 193 / 255, blue: 129 / 255)
    )
    private static let error = AdaptiveColor(
        light: Color(red: 207 / 255, green: 74 / 255, blue: 74 / 255),
        dark: Color(red: 238 / 255, green: 110 / 255, blue: 115 / 255)
    )

    public static func palette(for colorScheme: ColorScheme) -> Palette {
        Palette(colorScheme: colorScheme)
    }

    public struct Palette {
        private let colorScheme: ColorScheme

        public init(colorScheme: ColorScheme) {
            self.colorScheme = colorScheme
        }

        public var background: Color { AppColors.background.resolve(colorScheme) }
        public var cardBackground: Color { AppColors.cardBackground.resolve(colorScheme) }
        public var inputBackground: Color { AppColors.inputBackground.resolve(colorScheme) }
        public var accent: Color { AppColors.accent.resolve(colorScheme) }
        public var textPrimary: Color { AppColors.textPrimary.resolve(colorScheme) }
        public var textSecondary: Color { AppColors.textSecondary.resolve(colorScheme) }
        public var chipPrimaryBackground: Color { AppColors.chipPrimaryBackground.resolve(colorScheme) }
        public var chipSecondaryBackground: Color { AppColors.chipSecondaryBackground.resolve(colorScheme) }
        public var chipPrimaryText: Color { AppColors.chipPrimaryText.resolve(colorScheme) }
        public var chipSecondaryText: Color { AppColors.chipSecondaryText.resolve(colorScheme) }
        public var divider: Color { AppColors.divider.resolve(colorScheme) }
        public var skeleton: Color { AppColors.skeleton.resolve(colorScheme) }
        public var success: Color { AppColors.success.resolve(colorScheme) }
        public var error: Color { AppColors.error.resolve(colorScheme) }
    }

    private struct AdaptiveColor {
        private let light: Color
        private let dark: Color

        init(light: Color, dark: Color) {
            self.light = light
            self.dark = dark
        }

        func resolve(_ colorScheme: ColorScheme) -> Color {
            switch colorScheme {
            case .light:
                return light
            case .dark:
                return dark
            @unknown default:
                return dark
            }
        }
    }
}

public typealias AppColorPalette = AppColors.Palette
