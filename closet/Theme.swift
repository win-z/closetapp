//
//  Theme.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import SwiftUI

enum ClosetTheme {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let card = Color.white.opacity(0.92)
    static let secondaryCard = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let textPrimary = Color(red: 0.13, green: 0.18, blue: 0.29)
    static let textSecondary = Color(red: 0.44, green: 0.51, blue: 0.63)
    static let line = Color(red: 0.87, green: 0.9, blue: 0.95)
    static let indigo = Color(red: 0.33, green: 0.33, blue: 0.95)
    static let violet = Color(red: 0.68, green: 0.31, blue: 0.95)
    static let rose = Color(red: 0.95, green: 0.22, blue: 0.43)
    static let mint = Color(red: 0.18, green: 0.76, blue: 0.58)
    static let yellow = Color(red: 0.95, green: 0.69, blue: 0.06)
    static let sky = Color(red: 0.25, green: 0.49, blue: 0.94)
    static let slate = Color(red: 0.44, green: 0.51, blue: 0.63)

    static let accentGradient = LinearGradient(
        colors: [indigo, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let roseGradient = LinearGradient(
        colors: [rose, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let tabShadow = Color(red: 0.48, green: 0.55, blue: 0.7).opacity(0.18)
}

struct LayoutMetrics {
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat

    private let baseWidth: CGFloat = 430

    var scale: CGFloat {
        min(max(screenWidth / baseWidth, 0.86), 1.0)
    }

    var horizontalPadding: CGFloat { 18 * scale }
    var pageTopSpacing: CGFloat { max(12, safeTop * 0.4) }
    var contentWidth: CGFloat { screenWidth - horizontalPadding * 2 }
    var tabBarHeight: CGFloat { 88 * scale }
    var tabBarBottomPadding: CGFloat { max(10, safeBottom == 0 ? 12 : safeBottom - 2) }
    var tabInsetHeight: CGFloat { tabBarHeight + tabBarBottomPadding + 22 }
    var floatingActionBottomPadding: CGFloat { tabBarHeight + max(6, tabBarBottomPadding * 0.45) }
    var floatingPopoverBottomPadding: CGFloat { floatingActionBottomPadding + 46 * scale }

    func value(_ raw: CGFloat) -> CGFloat {
        raw * scale
    }
}
