//
//  MainTabView.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(
                screenWidth: proxy.size.width,
                screenHeight: proxy.size.height,
                safeTop: proxy.safeAreaInsets.top,
                safeBottom: proxy.safeAreaInsets.bottom
            )

            ZStack(alignment: .bottom) {
                ClosetTheme.background.ignoresSafeArea()

                currentScreen(metrics: metrics)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, metrics.tabInsetHeight)

                FloatingTabBar(selectedTab: Binding(
                    get: { appViewModel.selectedTab },
                    set: { appViewModel.selectedTab = $0 }
                ), metrics: metrics)
                .frame(maxWidth: 430)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, metrics.tabBarBottomPadding)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func currentScreen(metrics: LayoutMetrics) -> some View {
        switch appViewModel.selectedTab {
        case .wardrobe:
            WardrobeScreen(
                store: appViewModel.localStore,
                viewModel: appViewModel.wardrobeViewModel,
                selectedFilter: $appViewModel.selectedWardrobeCategory,
                searchText: $appViewModel.wardrobeSearchText,
                metrics: metrics
            )
        case .stylist:
            StylistScreen(
                store: appViewModel.localStore,
                mode: $appViewModel.stylistMode,
                metrics: metrics
            )
        case .calendar:
            CalendarScreen(
                store: appViewModel.localStore,
                viewModel: appViewModel.diaryViewModel,
                metrics: metrics
            )
        case .analytics:
            AnalyticsScreen(
                store: appViewModel.localStore,
                wardrobeViewModel: appViewModel.wardrobeViewModel,
                viewModel: appViewModel.analyticsViewModel,
                metrics: metrics
            )
        case .profile:
            ProfileScreen(
                store: appViewModel.localStore,
                profileViewModel: appViewModel.profileViewModel,
                metrics: metrics
            )
        }
    }

}
