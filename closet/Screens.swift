//
//  Screens.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum PageHeaderStyle {
    static func titleSize(for metrics: LayoutMetrics) -> CGFloat { metrics.value(28) }
    static func badgeSize(for metrics: LayoutMetrics) -> CGFloat { metrics.value(14) }
    static func badgeHorizontalPadding(for metrics: LayoutMetrics) -> CGFloat { metrics.value(10) }
    static func badgeVerticalPadding(for metrics: LayoutMetrics) -> CGFloat { metrics.value(6) }
    static func spacing(for metrics: LayoutMetrics) -> CGFloat { metrics.value(10) }
    static func minHeight(for metrics: LayoutMetrics) -> CGFloat { metrics.value(40) }
    static func sectionSpacing(for metrics: LayoutMetrics) -> CGFloat { metrics.value(16) }
    static func contentTopSpacing(for metrics: LayoutMetrics) -> CGFloat { metrics.value(12) }
    static func contentBottomSpacing(for metrics: LayoutMetrics) -> CGFloat { metrics.value(2) }
    static func actionHeight(for metrics: LayoutMetrics) -> CGFloat { metrics.value(40) }
    static func actionCornerRadius(for metrics: LayoutMetrics) -> CGFloat { metrics.value(14) }
    static func actionHorizontalPadding(for metrics: LayoutMetrics) -> CGFloat { metrics.value(12) }
    static func actionIconSize(for metrics: LayoutMetrics) -> CGFloat { metrics.value(12) }
    static func actionFontSize(for metrics: LayoutMetrics) -> CGFloat { metrics.value(13) }
    static func actionSpacing(for metrics: LayoutMetrics) -> CGFloat { metrics.value(6) }
    static func badgeCornerRadius(for metrics: LayoutMetrics) -> CGFloat { metrics.value(10) }
}

private struct HeaderBadgeView: View {
    let text: String
    let metrics: LayoutMetrics

    var body: some View {
        Text(text)
            .font(.system(size: PageHeaderStyle.badgeSize(for: metrics), weight: .black, design: .rounded))
            .foregroundStyle(ClosetTheme.rose)
            .padding(.horizontal, PageHeaderStyle.badgeHorizontalPadding(for: metrics))
            .padding(.vertical, PageHeaderStyle.badgeVerticalPadding(for: metrics))
            .background(Color(red: 1, green: 0.88, blue: 0.9))
            .clipShape(RoundedRectangle(cornerRadius: PageHeaderStyle.badgeCornerRadius(for: metrics)))
    }
}

private enum WardrobeAddEntryMode {
    case camera
    case photoLibrary
    case photoLibraryBatch
}

struct WardrobeScreen: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @ObservedObject var store: ClosetStore
    @ObservedObject var viewModel: WardrobeViewModel
    @Binding var selectedFilter: WardrobeFilter
    @Binding var searchText: String
    let metrics: LayoutMetrics

    @State private var isAddingItem = false
    @State private var isPresentingImportPicker = false
    @State private var selectedImportItems: [PhotosPickerItem] = []
    @State private var editingItem: ClosetItem?
    @State private var showingArchivedOnly = false
    @State private var deleteArmedItemID: UUID?
    @State private var pendingDeleteItem: ClosetItem?
    @State private var isBatchMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var isOutfitMode = false
    @State private var selectedOutfitItemIDs: Set<UUID> = []
    @State private var selectedColor = "全部颜色"
    @State private var selectedBrand = "全部品牌"
    @State private var wearFilter: LocalWearFilter = .all
    @State private var sortOption: LocalWardrobeSort = .newest
    @State private var isRenamingCloset = false
    @State private var pendingDeleteCloset = false
    @State private var closetDraftName = ""

    var filteredItems: [ClosetItem] {
        let source = showingArchivedOnly ? store.archivedWardrobeItems : store.activeWardrobeItems
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return source.filter { item in
            let matchesFilter = selectedFilter == .all || selectedFilter == item.section.filter
            let matchesColor = selectedColor == "全部颜色" || item.color == selectedColor
            let matchesBrand = selectedBrand == "全部品牌" || item.brand == selectedBrand
            let matchesWear: Bool
            switch wearFilter {
            case .all:
                matchesWear = true
            case .unworn:
                matchesWear = item.wearCount == 0
            case .worn:
                matchesWear = item.wearCount > 0
            }
            let haystack = [
                item.name,
                item.color,
                item.brand
            ].joined(separator: " ").lowercased()
            let matchesQuery = query.isEmpty || haystack.contains(query)
            return matchesFilter && matchesQuery && matchesColor && matchesBrand && matchesWear
        }
        .sorted(by: sortOption.comparator(store: store))
    }

    private var colorOptions: [String] {
        ["全部颜色"] + Array(Set((showingArchivedOnly ? store.archivedWardrobeItems : store.activeWardrobeItems).map(\.color))).sorted()
    }

    private var brandOptions: [String] {
        ["全部品牌"] + Array(Set((showingArchivedOnly ? store.archivedWardrobeItems : store.activeWardrobeItems).map(\.brand))).sorted()
    }

    private var selectedItems: [ClosetItem] {
        filteredItems.filter { selectedItemIDs.contains($0.id) }
    }

    private var selectedOutfitItems: [ClosetItem] {
        store.activeWardrobeItems.filter { selectedOutfitItemIDs.contains($0.id) }
    }

    private var orderedSections: [WardrobeSection] {
        [.top, .bottom, .shoes, .dress, .uncategorized]
    }

    private var groupedFilteredItems: [(section: WardrobeSection, items: [ClosetItem])] {
        orderedSections.compactMap { section in
            let items = filteredItems.filter { $0.section == section }
            return items.isEmpty ? nil : (section, items)
        }
    }

    @ViewBuilder
    private func wardrobeItemCard(_ item: ClosetItem) -> some View {
        LocalWardrobeItemCard(
            item: item,
            metrics: metrics,
            isDeleteArmed: deleteArmedItemID == item.id,
            showingArchivedStyle: showingArchivedOnly,
            onActionRevealTap: {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    deleteArmedItemID = deleteArmedItemID == item.id ? nil : item.id
                }
            },
            onDeleteRequest: {
                pendingDeleteItem = item
            },
            onToggleArchive: {
                store.toggleArchived(item.id)
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(showingArchivedOnly ? "恢复" : "归档") {
                store.toggleArchived(item.id)
            }
            .tint(showingArchivedOnly ? .blue : .orange)
            Button("删除", role: .destructive) {
                store.deleteItem(item.id)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("编辑") {
                editingItem = item
            }
            .tint(.green)
        }
        .contextMenu {
            Button(showingArchivedOnly ? "恢复到在穿" : "归档收纳") {
                store.toggleArchived(item.id)
            }
            Button("编辑") {
                editingItem = item
            }
            Button("删除", role: .destructive) {
                store.deleteItem(item.id)
            }
        }
        .onTapGesture {
            deleteArmedItemID = nil
            if isOutfitMode {
                if selectedOutfitItemIDs.contains(item.id) {
                    selectedOutfitItemIDs.remove(item.id)
                } else {
                    selectedOutfitItemIDs.insert(item.id)
                }
            } else if isBatchMode {
                if selectedItemIDs.contains(item.id) {
                    selectedItemIDs.remove(item.id)
                } else {
                    selectedItemIDs.insert(item.id)
                }
            } else {
                editingItem = item
            }
        }
        .overlay(alignment: .topLeading) {
            if isOutfitMode {
                Image(systemName: selectedOutfitItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: metrics.value(18), weight: .bold))
                    .foregroundStyle(selectedOutfitItemIDs.contains(item.id) ? ClosetTheme.rose : ClosetTheme.textSecondary.opacity(0.5))
                    .padding(metrics.value(8))
            } else if isBatchMode {
                Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: metrics.value(18), weight: .bold))
                    .foregroundStyle(selectedItemIDs.contains(item.id) ? ClosetTheme.indigo : ClosetTheme.textSecondary.opacity(0.5))
                    .padding(metrics.value(8))
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PageHeaderStyle.sectionSpacing(for: metrics)) {
                    PageHeader(
                        title: store.currentClosetName,
                        badge: "",
                        titleAccessory: {
                            HStack(alignment: .center, spacing: metrics.value(8)) {
                                HeaderBadgeView(text: "\(store.activeWardrobeItems.count) 件", metrics: metrics)
                                Menu {
                                    ForEach(store.closetSpaces) { closet in
                                        Button {
                                            store.selectCloset(closet.id)
                                        } label: {
                                            if closet.id == store.selectedClosetID {
                                                Label(closet.name, systemImage: "checkmark")
                                            } else {
                                                Text(closet.name)
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("新建衣橱") {
                                        store.createCloset()
                                    }
                                    Button("重命名当前衣橱") {
                                        closetDraftName = store.currentClosetName
                                        isRenamingCloset = true
                                    }
                                    Button("删除当前衣橱", role: .destructive) {
                                        pendingDeleteCloset = true
                                    }
                                    .disabled(store.closetSpaces.count <= 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: metrics.value(13), weight: .bold))
                                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.85))
                                        .frame(width: metrics.value(22), height: metrics.value(22))
                                }
                            }
                        },
                        metrics: metrics,
                        actions: {
                            if isOutfitMode {
                                HeaderCapsuleButton(title: "取消", icon: "xmark", filled: true, metrics: metrics)
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            isOutfitMode = false
                                            selectedOutfitItemIDs.removeAll()
                                        }
                                    }
                            } else {
                                WardrobeModeCluster(
                                    showingArchivedOnly: showingArchivedOnly,
                                    metrics: metrics,
                                    onArchiveTap: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            showingArchivedOnly.toggle()
                                        }
                                    },
                                    onOutfitTap: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            isBatchMode = false
                                            selectedItemIDs.removeAll()
                                            isOutfitMode = true
                                            selectedOutfitItemIDs.removeAll()
                                        }
                                    }
                                )
                            }
                        }
                    )

                SearchBar(text: $searchText, placeholder: "搜索名称、颜色、品牌...", metrics: metrics)
                    .padding(.top, PageHeaderStyle.contentTopSpacing(for: metrics))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.value(8)) {
                        ForEach(WardrobeFilter.allCases) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                selected: filter == selectedFilter,
                                metrics: metrics
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                    selectedFilter = filter
                                }
                            }
                        }

                        Menu {
                            ForEach(colorOptions, id: \.self) { color in
                                Button(color) { selectedColor = color }
                            }
                        } label: {
                            FilterChip(title: selectedColor, selected: selectedColor != "全部颜色", metrics: metrics)
                        }

                        Menu {
                            ForEach(brandOptions, id: \.self) { brand in
                                Button(brand) { selectedBrand = brand }
                            }
                        } label: {
                            FilterChip(title: selectedBrand, selected: selectedBrand != "全部品牌", metrics: metrics)
                        }

                        Menu {
                            ForEach(LocalWearFilter.allCases) { filter in
                                Button(filter.title) { wearFilter = filter }
                            }
                        } label: {
                            FilterChip(title: wearFilter.title, selected: wearFilter != .all, metrics: metrics)
                        }

                        Menu {
                            ForEach(LocalWardrobeSort.allCases) { option in
                                Button(option.title) { sortOption = option }
                            }
                        } label: {
                            FilterChip(title: sortOption.title, selected: sortOption != .newest, metrics: metrics)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.bottom, PageHeaderStyle.contentBottomSpacing(for: metrics))

                if isBatchMode {
                    FrostedCard {
                        VStack(alignment: .leading, spacing: metrics.value(12)) {
                            Text(selectedItemIDs.isEmpty ? "先点选要处理的单品" : "已选 \(selectedItemIDs.count) 件单品")
                                .font(.system(size: metrics.value(14), weight: .semibold))
                                .foregroundStyle(ClosetTheme.textPrimary)
                            HStack(spacing: metrics.value(8)) {
                                Button(showingArchivedOnly ? "批量恢复" : "批量归档") {
                                    store.setArchived(selectedItemIDs, isArchived: !showingArchivedOnly)
                                    selectedItemIDs.removeAll()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(showingArchivedOnly ? ClosetTheme.mint : ClosetTheme.rose)
                                .disabled(selectedItemIDs.isEmpty)

                                Button("批量删除", role: .destructive) {
                                    store.deleteItems(selectedItemIDs)
                                    selectedItemIDs.removeAll()
                                }
                                .buttonStyle(.bordered)
                                .disabled(selectedItemIDs.isEmpty)
                            }
                            if !selectedItems.isEmpty {
                                Text(selectedItems.prefix(3).map(\.name).joined(separator: "、"))
                                    .font(.system(size: metrics.value(12), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary)
                            }
                        }
                    }
                }

                if filteredItems.isEmpty {
                    VStack(spacing: metrics.value(12)) {
                        Image(systemName: "tshirt")
                            .font(.system(size: metrics.value(48), weight: .thin))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.35))
                        Text(searchText.isEmpty ? "该分类暂无单品" : "没有匹配到相关单品")
                            .font(.system(size: metrics.value(17), weight: .medium))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.value(40))
                } else {
                    VStack(alignment: .leading, spacing: metrics.value(20)) {
                        ForEach(groupedFilteredItems, id: \.section) { group in
                            VStack(alignment: .leading, spacing: metrics.value(10)) {
                                SectionHeaderLabel(
                                    title: group.section.rawValue,
                                    countText: "\(group.items.count)个",
                                    metrics: metrics
                                )

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: metrics.value(10)), count: 3),
                                    spacing: metrics.value(12)
                                ) {
                                    ForEach(group.items) { item in
                                        wardrobeItemCard(item)
                                    }
                                }
                            }
                        }
                    }
                }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.pageTopSpacing)
                .padding(.bottom, metrics.value(20))
            }

            if !isOutfitMode && !isBatchMode {
                FloatingAccentActionButton(
                    icon: "plus",
                    isExpanded: isPresentingImportPicker,
                    metrics: metrics
                )
                    .padding(.trailing, metrics.horizontalPadding)
                    .padding(.bottom, metrics.tabInsetHeight + metrics.value(8))
                    .onTapGesture {
                        isPresentingImportPicker = true
                    }
                    .zIndex(3)
            }
        }
        .sheet(isPresented: $isAddingItem, onDismiss: {
            selectedImportItems = []
        }) {
            AddItemSheet(
                store: store,
                metrics: metrics,
                initialPhotoItems: selectedImportItems
            )
        }
        .sheet(item: $editingItem) { item in
            AddItemSheet(store: store, metrics: metrics, editingItem: item)
        }
        .photosPicker(
            isPresented: $isPresentingImportPicker,
            selection: $selectedImportItems,
            maxSelectionCount: nil,
            matching: .images
        )
        .onChange(of: selectedImportItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            isAddingItem = true
        }
        .safeAreaInset(edge: .bottom) {
            if isOutfitMode {
                OutfitSelectionActionBar(
                    count: selectedOutfitItemIDs.count,
                    metrics: metrics,
                    onCancel: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            isOutfitMode = false
                            selectedOutfitItemIDs.removeAll()
                        }
                    },
                    onSave: {
                        let orderedIDs = store.activeWardrobeItems
                            .filter { selectedOutfitItemIDs.contains($0.id) }
                            .map(\.id)
                        guard !orderedIDs.isEmpty else { return }
                        guard store.saveManualOutfit(itemIDs: orderedIDs) != nil else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            isOutfitMode = false
                            selectedOutfitItemIDs.removeAll()
                        }
                        appViewModel.selectedTab = .stylist
                    }
                )
            }
        }
        .alert("删除这件单品？", isPresented: Binding(
            get: { pendingDeleteItem != nil },
            set: { if !$0 { pendingDeleteItem = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let item = pendingDeleteItem {
                    store.deleteItem(item.id)
                    deleteArmedItemID = nil
                }
                pendingDeleteItem = nil
            }
        } message: {
            Text("删除后，这件单品会从衣橱和相关搭配里移除。")
        }
        .alert("重命名衣橱", isPresented: $isRenamingCloset) {
            TextField("衣橱名称", text: $closetDraftName)
            Button("取消", role: .cancel) {
                closetDraftName = store.currentClosetName
            }
            Button("保存") {
                store.renameCurrentCloset(to: closetDraftName)
            }
        } message: {
            Text("修改当前衣橱的显示名称。")
        }
        .alert("删除当前衣橱？", isPresented: $pendingDeleteCloset) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteCloset(store.selectedClosetID)
            }
        } message: {
            Text(store.closetSpaces.count <= 1 ? "至少保留一个衣橱，当前不能删除。" : "删除后，这个衣橱里的衣服、搭配和记录都会被移除，身体资料不会受影响。")
        }
    }
}

private enum LocalWearFilter: CaseIterable, Identifiable {
    case all
    case unworn
    case worn

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部状态"
        case .unworn: "未穿过"
        case .worn: "穿过的"
        }
    }
}

private enum LocalWardrobeSort: CaseIterable, Identifiable {
    case newest
    case mostWorn
    case lowestPrice
    case highestPrice

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: "最新加入"
        case .mostWorn: "最常穿"
        case .lowestPrice: "价格最低"
        case .highestPrice: "价格最高"
        }
    }

    func comparator(store: ClosetStore) -> (ClosetItem, ClosetItem) -> Bool {
        switch self {
        case .newest:
            return { $0.createdAt > $1.createdAt }
        case .mostWorn:
            return { lhs, rhs in
                if lhs.wearCount == rhs.wearCount {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.wearCount > rhs.wearCount
            }
        case .lowestPrice:
            return { lhs, rhs in
                if lhs.price == rhs.price {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.price < rhs.price
            }
        case .highestPrice:
            return { lhs, rhs in
                if lhs.price == rhs.price {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.price > rhs.price
            }
        }
    }
}

private struct QuickLogItemCard: View {
    let item: ClosetItem
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(5)) {
            MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                .frame(width: metrics.value(76), height: metrics.value(96))
            Text(item.name)
                .font(.system(size: metrics.value(11), weight: .semibold))
                .foregroundStyle(ClosetTheme.textPrimary)
                .lineLimit(1)
            Text("已穿 \(item.wearCount) 次")
                .font(.system(size: metrics.value(10), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary)
        }
        .padding(metrics.value(7))
        .background(ClosetTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(18)))
    }
}

private struct LocalInsightPill: View {
    let title: String
    let value: String
    let color: Color
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(2)) {
            Text(value)
                .font(.system(size: metrics.value(20), weight: .heavy))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: metrics.value(11.5), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.value(12))
        .background(ClosetTheme.secondaryCard)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(14)))
    }
}

private struct WardrobeHeaderButton: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(6)) {
            Image(systemName: icon)
                .font(.system(size: metrics.value(12), weight: .semibold))
            Text(title)
                .font(.system(size: metrics.value(13), weight: .semibold))
        }
        .foregroundStyle(ClosetTheme.textSecondary)
        .padding(.horizontal, metrics.value(12))
        .frame(height: metrics.value(40))
        .background(ClosetTheme.secondaryCard)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(14)))
    }
}

private struct AddMethodPopover: View {
    let metrics: LayoutMetrics
    let onSelect: (WardrobeAddEntryMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            Text("添加方式")
                .font(.system(size: metrics.value(12), weight: .bold))
                .foregroundStyle(ClosetTheme.textSecondary)
                .padding(.horizontal, metrics.value(4))

            addButton(title: "拍照", subtitle: "直接拍一件衣服", icon: "camera.fill", tint: ClosetTheme.rose) {
                onSelect(.camera)
            }

            addButton(title: "从相册添加", subtitle: "单张导入后编辑信息", icon: "photo.fill", tint: ClosetTheme.indigo) {
                onSelect(.photoLibrary)
            }

            addButton(title: "从相册批量添加", subtitle: "直接导入为未分类", icon: "square.stack.3d.up.fill", tint: ClosetTheme.mint) {
                onSelect(.photoLibraryBatch)
            }
        }
        .padding(metrics.value(12))
        .frame(width: min(metrics.value(236), metrics.contentWidth * 0.68), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.value(24), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color(red: 0.96, green: 0.97, blue: 0.995).opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.value(24), style: .continuous)
                        .stroke(.white.opacity(0.75), lineWidth: 1)
                )
        )
        .shadow(color: ClosetTheme.tabShadow.opacity(0.9), radius: 18, y: 12)
        .overlay(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: metrics.value(4), style: .continuous)
                .fill(.white.opacity(0.92))
                .frame(width: metrics.value(16), height: metrics.value(16))
                .rotationEffect(.degrees(45))
                .offset(x: metrics.value(-22), y: metrics.value(8))
        }
    }

    private func addButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.value(12)) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: metrics.value(34), height: metrics.value(34))
                    Image(systemName: icon)
                        .font(.system(size: metrics.value(14), weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text(title)
                        .font(.system(size: metrics.value(14), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: metrics.value(11), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.value(12))
            .padding(.vertical, metrics.value(10))
            .background(
                RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.96), Color.white.opacity(0.76)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AIQuickGeneratePopover: View {
    @Binding var prompt: String
    let metrics: LayoutMetrics
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(10)) {
            HStack {
                Text("AI生成搭配")
                    .font(.system(size: metrics.value(15), weight: .heavy))
                    .foregroundStyle(ClosetTheme.textPrimary)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: metrics.value(14), weight: .bold))
                    .foregroundStyle(ClosetTheme.violet)
            }

            Text("输入一个场景或感觉，快速生成一套可以直接保存的搭配。")
                .font(.system(size: metrics.value(11.5), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary)

            TextField("例如：通勤、周末咖啡、极简黑白", text: $prompt, axis: .vertical)
                .font(.system(size: metrics.value(13), weight: .medium))
                .padding(.horizontal, metrics.value(12))
                .padding(.vertical, metrics.value(12))
                .background(
                    RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                                .stroke(ClosetTheme.line.opacity(0.7), lineWidth: 1)
                        )
                )

            Button(action: onGenerate) {
                HStack(spacing: metrics.value(6)) {
                    Image(systemName: "sparkles")
                    Text("立即生成")
                }
                .font(.system(size: metrics.value(14), weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.value(46))
                .background(ClosetTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))
            }
        }
        .padding(metrics.value(14))
        .frame(width: min(metrics.value(270), metrics.contentWidth * 0.76), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.value(24), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color(red: 0.96, green: 0.97, blue: 0.995).opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.value(24), style: .continuous)
                        .stroke(.white.opacity(0.78), lineWidth: 1)
                )
        )
        .shadow(color: ClosetTheme.tabShadow.opacity(0.95), radius: 18, y: 12)
        .overlay(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: metrics.value(4), style: .continuous)
                .fill(.white.opacity(0.92))
                .frame(width: metrics.value(16), height: metrics.value(16))
                .rotationEffect(.degrees(45))
                .offset(x: metrics.value(-22), y: metrics.value(8))
        }
    }
}

private struct WardrobeModeCluster: View {
    let showingArchivedOnly: Bool
    let metrics: LayoutMetrics
    let onArchiveTap: () -> Void
    let onOutfitTap: () -> Void

    var body: some View {
        HStack(spacing: metrics.value(8)) {
            modeButton(
                title: showingArchivedOnly ? "在穿" : "收纳",
                icon: showingArchivedOnly ? "tray.full" : "archivebox",
                emphasized: showingArchivedOnly
            ) {
                onArchiveTap()
            }

            modeButton(
                title: "搭配",
                icon: "square.on.square",
                emphasized: false
            ) {
                onOutfitTap()
            }
        }
    }

    private func modeButton(
        title: String,
        icon: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.value(6)) {
                Image(systemName: icon)
                    .font(.system(size: metrics.value(12), weight: .bold))
                Text(title)
                    .font(.system(size: metrics.value(13), weight: .bold))
            }
            .foregroundStyle(emphasized ? .white : ClosetTheme.textSecondary)
            .padding(.horizontal, metrics.value(12))
            .frame(height: metrics.value(38))
            .background(
                emphasized
                    ? AnyShapeStyle(ClosetTheme.accentGradient)
                    : AnyShapeStyle(ClosetTheme.secondaryCard.opacity(0.92))
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(14), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(14), style: .continuous)
                    .stroke(emphasized ? .white.opacity(0.34) : ClosetTheme.line.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OutfitSelectionActionBar: View {
    let count: Int
    let metrics: LayoutMetrics
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: metrics.value(12)) {
            Button("取消", action: onCancel)
                .font(.system(size: metrics.value(15), weight: .semibold))
                .foregroundStyle(ClosetTheme.textSecondary)
                .frame(width: metrics.value(86), height: metrics.value(50))
                .background(ClosetTheme.secondaryCard)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))

            VStack(alignment: .leading, spacing: metrics.value(2)) {
                Text(count == 0 ? "选择衣服创建搭配" : "已选 \(count) 件")
                    .font(.system(size: metrics.value(14), weight: .bold))
                    .foregroundStyle(ClosetTheme.textPrimary)
                Text("保存后会进入我的搭配")
                    .font(.system(size: metrics.value(11), weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button(action: onSave) {
                HStack(spacing: metrics.value(6)) {
                    Image(systemName: "bookmark.fill")
                    Text("保存搭配")
                }
                .font(.system(size: metrics.value(15), weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.value(16))
                .frame(height: metrics.value(50))
                .background(ClosetTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))
            }
            .disabled(count == 0)
            .opacity(count == 0 ? 0.55 : 1)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.value(12))
        .padding(.bottom, metrics.value(2))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.72))
                .frame(height: 1)
        }
        .offset(y: metrics.value(5))
    }
}

struct WardrobeSummaryChip: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(6)) {
            Image(systemName: icon)
                .font(.system(size: metrics.value(13), weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: metrics.value(15), weight: .heavy))
                .foregroundStyle(ClosetTheme.textPrimary)
            Text(label)
                .font(.system(size: metrics.value(13), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary)
        }
        .padding(.horizontal, metrics.value(12))
        .padding(.vertical, metrics.value(8))
        .background(ClosetTheme.secondaryCard)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
    }
}

struct StylistScreen: View {
    @ObservedObject var store: ClosetStore
    @Binding var mode: StylistMode
    let metrics: LayoutMetrics

    @State private var aiPrompt = ""
    @State private var searchText = ""
    @State private var selectedFilter: WardrobeFilter = .all
    @State private var showingGenerateSheet = false
    @State private var isGeneratingAIOutfit = false
    @State private var aiGenerationErrorMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PageHeaderStyle.sectionSpacing(for: metrics)) {

                    PageHeader(
                        title: "我的搭配",
                        badge: "\(store.activeSavedLooks.count) 套",
                        titleAccessory: { EmptyView() },
                        metrics: metrics,
                        actions: { EmptyView() }
                    )

                    SearchBar(text: $searchText, placeholder: "搜索搭配名称、单品名...", metrics: metrics)
                        .padding(.top, PageHeaderStyle.contentTopSpacing(for: metrics))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: metrics.value(8)) {
                            ForEach([WardrobeFilter.all, .top, .bottom, .shoes, .dress, .uncategorized], id: \.id) { filter in
                                FilterChip(
                                    title: filter.rawValue,
                                    selected: filter == selectedFilter,
                                    metrics: metrics
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                        selectedFilter = filter
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .padding(.bottom, PageHeaderStyle.contentBottomSpacing(for: metrics))

                    SavedOutfitsGrid(
                        store: store,
                        metrics: metrics,
                        selectedFilter: selectedFilter,
                        searchText: searchText
                    )
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.pageTopSpacing)
                .padding(.bottom, metrics.value(20))
            }
            .blur(radius: showingGenerateSheet ? 1.5 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: showingGenerateSheet)

            if showingGenerateSheet {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                            showingGenerateSheet = false
                        }
                    }

                AIQuickGeneratePopover(
                    prompt: $aiPrompt,
                    metrics: metrics,
                    onGenerate: {
                        guard !isGeneratingAIOutfit else { return }
                        isGeneratingAIOutfit = true
                        aiGenerationErrorMessage = nil

                        Task {
                            do {
                                let generatedOutfit = try await store.makeAIOutfit(prompt: aiPrompt)
                                await MainActor.run {
                                    mode = .ai
                                    if generatedOutfit == nil {
                                        aiGenerationErrorMessage = "当前至少需要 1 件上装、1 件下装和 1 双鞋，才能生成 AI 搭配图。"
                                    } else {
                                        aiPrompt = ""
                                        showingGenerateSheet = false
                                    }
                                    isGeneratingAIOutfit = false
                                }
                            } catch {
                                await MainActor.run {
                                    aiGenerationErrorMessage = error.localizedDescription
                                    isGeneratingAIOutfit = false
                                }
                            }
                        }
                    }
                )
                .padding(.trailing, metrics.horizontalPadding)
                .padding(.bottom, metrics.tabInsetHeight + metrics.value(54))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            FloatingAccentActionButton(
                icon: "sparkles",
                isExpanded: showingGenerateSheet,
                metrics: metrics
            )
                .padding(.trailing, metrics.horizontalPadding)
                .padding(.bottom, metrics.tabInsetHeight + metrics.value(8))
                .onTapGesture {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                        showingGenerateSheet.toggle()
                    }
                }
        }
        .overlay {
            if isGeneratingAIOutfit {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    ProgressView("正在生成 AI 搭配图...")
                        .padding(.horizontal, metrics.value(18))
                        .padding(.vertical, metrics.value(14))
                        .background(
                            RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        }
        .alert(
            "生成失败",
            isPresented: Binding(
                get: { aiGenerationErrorMessage != nil },
                set: { if !$0 { aiGenerationErrorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                aiGenerationErrorMessage = nil
            }
        } message: {
            Text(aiGenerationErrorMessage ?? "请稍后重试")
        }
    }
}

// MARK: - Saved Outfits Grid
private struct SavedOutfitsGrid: View {
    @ObservedObject var store: ClosetStore
    let metrics: LayoutMetrics
    let selectedFilter: WardrobeFilter
    let searchText: String

    @State private var selectedLook: OutfitPreview?
    @State private var deleteArmedLookID: UUID?
    @State private var pendingDeleteLook: OutfitPreview?

    private var activeItemMap: [UUID: ClosetItem] {
        Dictionary(uniqueKeysWithValues: store.activeWardrobeItems.map { ($0.id, $0) })
    }

    private var lookContexts: [LookContext] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return store.activeSavedLooks.compactMap { look in
            let linkedItems = look.itemIDs.compactMap { activeItemMap[$0] }
            let primaryFilter = primaryFilter(for: linkedItems)
            let matchesFilter = selectedFilter == .all || linkedItems.contains { $0.section.filter == selectedFilter }
            let haystack = ([look.title, look.subtitle] + linkedItems.map(\.name)).joined(separator: " ").lowercased()
            let matchesQuery = query.isEmpty || haystack.contains(query)
            guard matchesFilter && matchesQuery else { return nil }
            return LookContext(look: look, linkedItems: linkedItems, primaryFilter: primaryFilter)
        }
    }

    private var groupedLooks: [(section: WardrobeFilter, looks: [LookContext])] {
        let order: [WardrobeFilter] = [.top, .bottom, .shoes, .dress, .uncategorized]
        let grouped = Dictionary(grouping: lookContexts, by: \.primaryFilter)
        return order.compactMap { filter in
            guard let looks = grouped[filter], !looks.isEmpty else { return nil }
            return (filter, looks)
        }
    }

    var body: some View {
        if lookContexts.isEmpty {
            EmptyStateCard(
                icon: "bookmark",
                title: "还没有保存搭配",
                subtitle: "点右上角「AI生成」，快速创建你的第一套搭配。",
                metrics: metrics
            )
            .padding(.top, metrics.value(20))
        } else {
            VStack(alignment: .leading, spacing: metrics.value(20)) {
                ForEach(groupedLooks, id: \.section) { group in
                    VStack(alignment: .leading, spacing: metrics.value(10)) {
                        SectionHeaderLabel(
                            title: group.section.rawValue,
                            countText: "\(group.looks.count)套",
                            metrics: metrics
                        )

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: metrics.value(10)), count: 3),
                            spacing: metrics.value(12)
                        ) {
                            ForEach(group.looks) { context in
                                OutfitLookCard(
                                    look: context.look,
                                    linkedItems: context.linkedItems,
                                    metrics: metrics,
                                    isDeleteArmed: deleteArmedLookID == context.look.id,
                                    onDeleteControlTap: {
                                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                            deleteArmedLookID = deleteArmedLookID == context.look.id ? nil : context.look.id
                                        }
                                    },
                                    onDeleteRequest: {
                                        pendingDeleteLook = context.look
                                    }
                                )
                                .onTapGesture {
                                    deleteArmedLookID = nil
                                    selectedLook = context.look
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedLook) { look in
                OutfitDetailSheet(store: store, look: look, metrics: metrics)
            }
            .alert("删除这套搭配？", isPresented: Binding(
                get: { pendingDeleteLook != nil },
                set: { if !$0 { pendingDeleteLook = nil } }
            )) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let look = pendingDeleteLook {
                        store.deleteOutfit(look.id)
                        deleteArmedLookID = nil
                    }
                    pendingDeleteLook = nil
                }
            } message: {
                Text("删除后，这套手动或 AI 搭配将从已保存列表中移除。")
            }
        }
    }

    private func primaryFilter(for linkedItems: [ClosetItem]) -> WardrobeFilter {
        let filters = Set(linkedItems.map { $0.section.filter })
        if filters.contains(.top) { return .top }
        if filters.contains(.bottom) { return .bottom }
        if filters.contains(.shoes) { return .shoes }
        if filters.contains(.dress) { return .dress }
        return .uncategorized
    }

    private struct LookContext: Identifiable {
        let look: OutfitPreview
        let linkedItems: [ClosetItem]
        let primaryFilter: WardrobeFilter

        var id: UUID { look.id }
    }
}


struct CalendarScreen: View {
    @ObservedObject var store: ClosetStore
    @ObservedObject var viewModel: DiaryViewModel
    @EnvironmentObject private var appViewModel: AppViewModel
    let metrics: LayoutMetrics

    @State private var displayedMonth = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var isEditingDiary = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.firstWeekday = 1
        return value
    }

    private var numberOfDays: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private var monthStartDate: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    }

    private var leadingEmptyDays: Int {
        max(calendar.component(.weekday, from: monthStartDate) - calendar.firstWeekday, 0)
    }

    private var calendarSlots: [Int?] {
        let days = Array(repeating: Optional<Int>.none, count: leadingEmptyDays) + (1...numberOfDays).map(Optional.some)
        let trailingCount = (7 - (days.count % 7)) % 7
        return days + Array(repeating: Optional<Int>.none, count: trailingCount)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: displayedMonth)
    }

    private var markers: [DiaryMarker] {
        if appViewModel.authState == .signedIn {
            return viewModel.markers(for: displayedMonth)
        }
        return store.markers(for: displayedMonth)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PageHeaderStyle.sectionSpacing(for: metrics)) {
                PageHeader(
                    title: "穿搭日记",
                    badge: "OOTD",
                    titleAccessory: { EmptyView() },
                    metrics: metrics,
                    actions: {
                        HeaderCapsuleButton(title: "记录", icon: "plus", metrics: metrics)
                            .onTapGesture {
                                selectedDate = calendar.startOfDay(for: .now)
                                isEditingDiary = true
                            }
                    }
                )

                FrostedCard(padding: 0) {
                    VStack(spacing: 0) {
                        VStack(spacing: metrics.value(14)) {
                            HStack {
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.white.opacity(0.9))
                                    .onTapGesture {
                                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                                    }
                                Spacer()
                                Text(monthTitle)
                                    .font(.system(size: metrics.value(24), weight: .heavy))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.9))
                                    .onTapGesture {
                                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                                    }
                            }
                            .font(.system(size: metrics.value(24), weight: .semibold))

                            HStack {
                                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                                    Text(day)
                                        .frame(maxWidth: .infinity)
                                        .font(.system(size: metrics.value(13), weight: .bold))
                                        .foregroundStyle(.white.opacity(0.82))
                                }
                            }
                        }
                        .padding(.horizontal, metrics.value(18))
                        .padding(.top, metrics.value(18))
                        .padding(.bottom, metrics.value(14))
                        .background(ClosetTheme.accentGradient)

                        VStack(spacing: 0) {
                            Divider()
                                .overlay(ClosetTheme.line.opacity(0.9))

                            LazyVGrid(columns: columns, spacing: 0) {
                                ForEach(Array(calendarSlots.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        let date = dateFor(day: day)
                                        CalendarDayCell(
                                            day: day,
                                            marker: markers.first(where: { $0.day == day }),
                                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                            metrics: metrics
                                        )
                                        .onTapGesture {
                                            selectedDate = date
                                        }
                                    } else {
                                        CalendarDayCell(
                                            day: nil,
                                            marker: nil,
                                            isSelected: false,
                                            metrics: metrics
                                        )
                                    }
                                }
                            }
                        }
                        .background(Color.white.opacity(0.76))

                        HStack(spacing: metrics.value(22)) {
                            LegendDot(color: ClosetTheme.rose, title: "有照片", metrics: metrics)
                            LegendDot(color: ClosetTheme.indigo, title: "有搭配", metrics: metrics)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, metrics.value(10))
                    }
                }

                TodayOutfitSection(
                    store: store,
                    date: selectedDate,
                    metrics: metrics,
                    onEdit: {
                        isEditingDiary = true
                    }
                )
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.pageTopSpacing)
            .padding(.bottom, metrics.value(8))
        }
        .sheet(isPresented: $isEditingDiary) {
            if appViewModel.authState == .signedIn {
                RemoteDiaryEntrySheet(
                    viewModel: viewModel,
                    date: selectedDate,
                    defaultWeather: store.weather.condition
                )
            } else {
                DiaryEntrySheet(store: store, date: selectedDate, metrics: metrics)
            }
        }
        .task {
            guard appViewModel.authState == .signedIn else { return }
            guard viewModel.entries.isEmpty else { return }
            await viewModel.loadDiaryEntries()
        }
    }

    private func dateFor(day: Int) -> Date {
        calendar.date(bySetting: .day, value: day, of: displayedMonth) ?? displayedMonth
    }

    private var remoteSelectedEntry: RemoteDiaryEntry? {
        guard appViewModel.authState == .signedIn else { return nil }
        return viewModel.entry(for: selectedDate)
    }

    private var selectedDateLabel: String {
        if calendar.isDateInToday(selectedDate) {
            return "今天"
        }
        if calendar.isDateInYesterday(selectedDate) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: selectedDate)
    }
}


// MARK: - AnalyticsScreen
struct AnalyticsScreen: View {
    @ObservedObject var store: ClosetStore
    @ObservedObject var wardrobeViewModel: WardrobeViewModel
    @ObservedObject var viewModel: AnalyticsViewModel
    @EnvironmentObject private var appViewModel: AppViewModel
    let metrics: LayoutMetrics

    // 0=总览, 1=品牌, 2=价格, 3=穿着
    @State private var selectedTab = 0
    @State private var showingAISheet = false

    private let tabs = [
        (title: "总览",  icon: "arrow.up.right"),
        (title: "品牌",  icon: "tag"),
        (title: "价格",  icon: "dollarsign"),
        (title: "穿着",  icon: "tshirt")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: metrics.value(14)) {

                PageHeader(
                    title: "衣橱分析",
                    badge: "STATS",
                    titleAccessory: { EmptyView() },
                    metrics: metrics,
                    actions: {
                        HStack(spacing: metrics.value(8)) {
                            HeaderCapsuleButton(title: "刷新", icon: "arrow.clockwise", filled: true, metrics: metrics)
                                .onTapGesture {}
                            HeaderCapsuleButton(title: "AI", icon: "sparkles", metrics: metrics)
                                .onTapGesture { showingAISheet = true }
                        }
                    }
                )

                // ── Tab Bar ───────────────────────────────────────
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.value(8)) {
                        ForEach(tabs.indices, id: \.self) { idx in
                            let tab = tabs[idx]
                            FilterChip(
                                title: tab.title,
                                selected: selectedTab == idx,
                                metrics: metrics
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                    selectedTab = idx
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.bottom, PageHeaderStyle.contentBottomSpacing(for: metrics))

                // ── Tab Content ───────────────────────────────────
                switch selectedTab {
                case 0: AnalyticsOverviewTab(store: store, viewModel: viewModel, items: analyticsSourceItems, metrics: metrics, onAITap: { showingAISheet = true })
                case 1: AnalyticsBrandTab(items: analyticsSourceItems, metrics: metrics)
                case 2: AnalyticsPriceTab(items: analyticsSourceItems, metrics: metrics)
                case 3: AnalyticsWearTab(store: store, items: analyticsSourceItems, metrics: metrics)
                default: EmptyView()
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.pageTopSpacing)
            .padding(.bottom, metrics.value(20))
        }
        .sheet(isPresented: $showingAISheet) {
            AIDeepAnalysisSheet(viewModel: viewModel, metrics: metrics)
        }
    }

    // MARK: Helpers
    private var remoteWardrobeItems: [ClosetItem] {
        wardrobeViewModel.items.map { item in
            ClosetItem(
                name: item.name,
                section: WardrobeSection(category: item.category),
                color: item.color,
                brand: item.brand ?? "未填写品牌",
                price: Int(item.price ?? 0),
                wearCount: item.wearCount,
                gradientName: WardrobeSection(category: item.category).defaultGradientName
            )
        }
    }
    private var analyticsSourceItems: [ClosetItem] {
        appViewModel.authState == .signedIn ? remoteWardrobeItems : store.activeWardrobeItems
    }
}

// MARK: - Overview Tab
private struct AnalyticsOverviewTab: View {
    @ObservedObject var store: ClosetStore
    @ObservedObject var viewModel: AnalyticsViewModel
    let items: [ClosetItem]
    let metrics: LayoutMetrics
    var onAITap: () -> Void

    var body: some View {
        VStack(spacing: metrics.value(16)) {
            // AI 深度报告横幅
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: metrics.value(18))
                    .fill(
                        LinearGradient(
                            colors: [Color(hue: 0.71, saturation: 0.65, brightness: 0.88),
                                     Color(hue: 0.78, saturation: 0.72, brightness: 0.74)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: metrics.value(10)) {
                    HStack(spacing: metrics.value(8)) {
                        Image(systemName: "sparkles")
                            .font(.system(size: metrics.value(22), weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("深度报告已就绪")
                            .font(.system(size: metrics.value(18), weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    Text("AI 已根据您的衣橱数据生成了专业的风格建议与健康度报告。")
                        .font(.system(size: metrics.value(13), weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: metrics.value(10)) {
                        Button {
                            onAITap()
                        } label: {
                            Text("查看深度报告")
                                .font(.system(size: metrics.value(13.5), weight: .bold))
                                .foregroundStyle(Color(hue: 0.73, saturation: 0.6, brightness: 0.8))
                                .padding(.horizontal, metrics.value(16))
                                .padding(.vertical, metrics.value(9))
                                .background(.white)
                                .clipShape(Capsule())
                        }
                        Button {
                            onAITap()
                        } label: {
                            Text("更新分析")
                                .font(.system(size: metrics.value(13.5), weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, metrics.value(16))
                                .padding(.vertical, metrics.value(9))
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(metrics.value(20))
            }

            // 3 big stats
            HStack(spacing: 0) {
                OverviewBigStat(value: "\(items.count)", label: "总单品数", color: ClosetTheme.indigo, metrics: metrics)
                Divider().frame(height: metrics.value(40)).opacity(0.2)
                OverviewBigStat(value: "\(Set(items.map { $0.section.rawValue }).count)", label: "品类数", color: ClosetTheme.mint, metrics: metrics)
                Divider().frame(height: metrics.value(40)).opacity(0.2)
                OverviewBigStat(value: "\(Set(items.map { $0.color }).count)", label: "颜色数", color: ClosetTheme.rose, metrics: metrics)
            }
            .padding(.vertical, metrics.value(12))
            .background(ClosetTheme.secondaryCard)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(16)))

            // 品类构成 donut
            FrostedCard {
                VStack(spacing: metrics.value(14)) {
                    Text("品类构成")
                        .font(.system(size: metrics.value(16), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    CategoryDonutChart(items: items, metrics: metrics)
                        .frame(height: metrics.value(170))
                }
            }

            if !store.idleItems(forMoreThan: 30).isEmpty || store.newestItemsCount() > 0 {
                FrostedCard {
                    VStack(alignment: .leading, spacing: metrics.value(12)) {
                        Text("本地提醒")
                            .font(.system(size: metrics.value(16), weight: .bold))
                            .foregroundStyle(ClosetTheme.textPrimary)
                        HStack(spacing: metrics.value(10)) {
                            LocalInsightPill(title: "近 7 天新增", value: "\(store.newestItemsCount())", color: ClosetTheme.indigo, metrics: metrics)
                            LocalInsightPill(title: "闲置 30 天+", value: "\(store.idleItems(forMoreThan: 30).count)", color: ClosetTheme.rose, metrics: metrics)
                        }
                        if let item = store.idleItems(forMoreThan: 30).first {
                            Text("最该翻出来穿的一件：\(item.name)")
                                .font(.system(size: metrics.value(13), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewBigStat: View {
    let value: String; let label: String; let color: Color; let metrics: LayoutMetrics
    var body: some View {
        VStack(spacing: metrics.value(4)) {
            Text(value).font(.system(size: metrics.value(32), weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: metrics.value(12), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Donut Chart
private struct CategoryDonutChart: View {
    let items: [ClosetItem]; let metrics: LayoutMetrics
    private let colors: [Color] = [ClosetTheme.indigo, ClosetTheme.mint, ClosetTheme.rose, Color.orange, Color.yellow]

    private var segments: [(label: String, count: Int, ratio: Double, color: Color)] {
        let groups = Dictionary(grouping: items, by: { $0.section.rawValue })
        let total = max(items.count, 1)
        return groups.enumerated().map { (idx, pair) in
            (label: pair.key, count: pair.value.count, ratio: Double(pair.value.count) / Double(total), color: colors[idx % colors.count])
        }.sorted { $0.count > $1.count }
    }

    var body: some View {
        HStack(spacing: metrics.value(20)) {
            Canvas { ctx, size in
                let cx = size.width / 2; let cy = size.height / 2
                let r = min(cx, cy) * 0.85; let innerR = r * 0.55
                var start = -Double.pi / 2
                for seg in segments {
                    let sweep = seg.ratio * 2 * .pi
                    var path = Path()
                    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
                    path.addArc(center: CGPoint(x: cx, y: cy), radius: innerR, startAngle: .radians(start + sweep), endAngle: .radians(start), clockwise: true)
                    path.closeSubpath()
                    ctx.fill(path, with: .color(seg.color))
                    start += sweep
                }
            }
            .frame(width: metrics.value(150), height: metrics.value(150))

            VStack(alignment: .leading, spacing: metrics.value(8)) {
                ForEach(segments, id: \.label) { seg in
                    HStack(spacing: metrics.value(8)) {
                        Circle().fill(seg.color).frame(width: metrics.value(9), height: metrics.value(9))
                        Text(seg.label).font(.system(size: metrics.value(13), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
                        Spacer()
                        Text("\(seg.count)件").font(.system(size: metrics.value(13), weight: .bold)).foregroundStyle(ClosetTheme.textPrimary)
                    }
                }
                if items.isEmpty {
                    Text("暂无数据").font(.system(size: metrics.value(13))).foregroundStyle(ClosetTheme.textSecondary.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, metrics.value(4))
    }
}

// MARK: - Brand Tab
private struct AnalyticsBrandTab: View {
    let items: [ClosetItem]; let metrics: LayoutMetrics

    private struct BrandSummary: Identifiable {
        let id = UUID(); let name: String; let count: Int; let totalPrice: Int; let sampleItems: [ClosetItem]
    }

    private var brands: [BrandSummary] {
        let groups = Dictionary(grouping: items, by: { $0.brand })
        return groups.map { BrandSummary(name: $0.key, count: $0.value.count, totalPrice: $0.value.reduce(0) { $0 + $1.price }, sampleItems: Array($0.value.prefix(2))) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: metrics.value(4)) {
                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text("品牌偏好")
                        .font(.system(size: metrics.value(16), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    Text("共 \(brands.count) 个品牌")
                        .font(.system(size: metrics.value(12), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.6))
                }
                .padding(.bottom, metrics.value(8))

                if brands.isEmpty {
                    EmptyStateCard(icon: "tag", title: "暂无品牌数据", subtitle: "添加衣橱单品并填写品牌后，这里会显示品牌分析。", metrics: metrics)
                } else {
                    ForEach(Array(brands.enumerated()), id: \.element.id) { (idx, brand) in
                        VStack(spacing: 0) {
                            HStack(spacing: metrics.value(14)) {
                                Text("\(idx + 1)")
                                    .font(.system(size: metrics.value(15), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.4))
                                    .frame(width: metrics.value(18))

                                VStack(alignment: .leading, spacing: metrics.value(3)) {
                                    Text(brand.name)
                                        .font(.system(size: metrics.value(15), weight: .semibold))
                                        .foregroundStyle(ClosetTheme.textPrimary)
                                    Text("\(brand.count)件 · ¥\(brand.totalPrice.formatted())")
                                        .font(.system(size: metrics.value(12), weight: .medium))
                                        .foregroundStyle(ClosetTheme.textSecondary)
                                }
                                Spacer()
                                HStack(spacing: metrics.value(4)) {
                                    ForEach(brand.sampleItems) { item in
                                        MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                                            .frame(width: metrics.value(46), height: metrics.value(62))
                                    }
                                }
                            }
                            .padding(.vertical, metrics.value(12))
                            if idx < brands.count - 1 {
                                Divider().overlay(ClosetTheme.line.opacity(0.4))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Price Tab
private struct AnalyticsPriceTab: View {
    let items: [ClosetItem]; let metrics: LayoutMetrics

    private var totalValue: Int { items.reduce(0) { $0 + $1.price } }
    private var avgPrice: Int { items.isEmpty ? 0 : totalValue / items.count }
    private var maxPrice: Int { items.map(\.price).max() ?? 0 }
    private var pricedCount: Int { items.filter { $0.price > 0 }.count }

    private var priceBands: [(range: String, count: Int, ratio: Double)] {
        let total = max(items.count, 1)
        let bands: [(String, (Int) -> Bool)] = [
            ("0-100", { $0 < 100 }),
            ("100-300", { $0 >= 100 && $0 < 300 }),
            ("300-500", { $0 >= 300 && $0 < 500 }),
            ("500-1000", { $0 >= 500 && $0 < 1000 }),
            ("1000+", { $0 >= 1000 })
        ]
        return bands.map { (r, pred) in
            let c = items.filter { pred($0.price) }.count
            return (range: r, count: c, ratio: Double(c) / Double(total))
        }
    }

    private var bestValueItems: [ClosetItem] {
        items.filter { $0.wearCount > 0 }
            .sorted { Double($0.price) / Double($0.wearCount) < Double($1.price) / Double($1.wearCount) }
    }

    var body: some View {
        VStack(spacing: metrics.value(14)) {
            // 2x2 big stats
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: metrics.value(2)) {
                PriceBigStat(value: "¥\(totalValue.formatted())", label: "总价值", color: ClosetTheme.mint, metrics: metrics)
                PriceBigStat(value: "¥\(avgPrice.formatted())", label: "平均单价", color: ClosetTheme.indigo, metrics: metrics)
                PriceBigStat(value: "¥\(maxPrice.formatted())", label: "最贵单品", color: ClosetTheme.rose, metrics: metrics)
                PriceBigStat(value: "\(pricedCount)/\(items.count)", label: "已标价/总数", color: Color.orange, metrics: metrics)
            }

            // Price bands
            FrostedCard {
                VStack(alignment: .leading, spacing: metrics.value(10)) {
                    Text("价格区间分布")
                        .font(.system(size: metrics.value(15), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    ForEach(priceBands, id: \.range) { band in
                        HStack(spacing: metrics.value(8)) {
                            Text(band.range)
                                .frame(width: metrics.value(68), alignment: .leading)
                                .font(.system(size: metrics.value(12.5), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(ClosetTheme.secondaryCard)
                                    Capsule().fill(ClosetTheme.accentGradient)
                                        .frame(width: proxy.size.width * band.ratio)
                                }
                            }
                            .frame(height: metrics.value(11))
                            Text("\(band.count)")
                                .font(.system(size: metrics.value(13), weight: .bold))
                                .foregroundStyle(band.count > 0 ? ClosetTheme.indigo : ClosetTheme.textSecondary.opacity(0.35))
                                .frame(width: metrics.value(18))
                        }
                    }
                }
            }

            // Best value list
            if !bestValueItems.isEmpty {
                VStack(alignment: .leading, spacing: metrics.value(8)) {
                    HStack(spacing: metrics.value(6)) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: metrics.value(14), weight: .semibold))
                            .foregroundStyle(ClosetTheme.mint)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("最划算单品").font(.system(size: metrics.value(15), weight: .bold)).foregroundStyle(ClosetTheme.mint)
                            Text("价格 ÷ 穿着次数，越低越划").font(.system(size: metrics.value(11.5), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
                        }
                    }
                    FrostedCard {
                        VStack(spacing: 0) {
                            ForEach(Array(bestValueItems.prefix(5).enumerated()), id: \.element.id) { (idx, item) in
                                VStack(spacing: 0) {
                                    HStack(spacing: metrics.value(12)) {
                                        ZStack {
                                            Circle().fill(ClosetTheme.accentGradient).frame(width: metrics.value(26), height: metrics.value(26))
                                            Text("\(idx + 1)").font(.system(size: metrics.value(12), weight: .heavy)).foregroundStyle(.white)
                                        }
                                        MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                                            .frame(width: metrics.value(50), height: metrics.value(68))
                                        VStack(alignment: .leading, spacing: metrics.value(3)) {
                                            Text(item.name).font(.system(size: metrics.value(14), weight: .semibold)).foregroundStyle(ClosetTheme.textPrimary)
                                            Text("¥\(item.price) ÷ \(item.wearCount)次").font(.system(size: metrics.value(12), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 0) {
                                            Text("¥\(String(format: "%.1f", Double(item.price) / Double(item.wearCount)))").font(.system(size: metrics.value(15), weight: .heavy)).foregroundStyle(ClosetTheme.mint)
                                            Text("每次").font(.system(size: metrics.value(11), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, metrics.value(10))
                                    if idx < min(bestValueItems.count, 5) - 1 {
                                        Divider().overlay(ClosetTheme.line.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PriceBigStat: View {
    let value: String; let label: String; let color: Color; let metrics: LayoutMetrics
    var body: some View {
        VStack(spacing: metrics.value(4)) {
            Text(value).font(.system(size: metrics.value(24), weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: metrics.value(12), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.value(16))
    }
}

// MARK: - Wear Tab
private struct AnalyticsWearTab: View {
    @ObservedObject var store: ClosetStore
    let items: [ClosetItem]; let metrics: LayoutMetrics

    private var wornItems: [ClosetItem] { items.filter { $0.wearCount > 0 } }
    private var unwornItems: [ClosetItem] { items.filter { $0.wearCount == 0 } }
    private var mostWorn: [ClosetItem] { items.sorted { $0.wearCount > $1.wearCount }.filter { $0.wearCount > 0 } }
    private var idleItems: [ClosetItem] { store.idleItems(forMoreThan: 30) }

    var body: some View {
        VStack(spacing: metrics.value(14)) {
            // 已穿 / 未穿
            HStack(spacing: 0) {
                WearBigStat(value: "\(wornItems.count)", label: "已穿着单品", color: ClosetTheme.mint, metrics: metrics)
                Divider().frame(height: metrics.value(40)).opacity(0.2)
                WearBigStat(value: "\(unwornItems.count)", label: "未穿着单品", color: ClosetTheme.rose, metrics: metrics)
            }
            .padding(.vertical, metrics.value(14))
            .background(ClosetTheme.secondaryCard)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(16)))

            // Most worn list
            FrostedCard {
                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text("最常穿着")
                        .font(.system(size: metrics.value(16), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .padding(.bottom, metrics.value(6))

                    if mostWorn.isEmpty {
                        EmptyStateCard(icon: "tshirt", title: "暂无穿着记录", subtitle: "在「记录」页添加穿搭日记后，穿着频率会显示在这里。", metrics: metrics)
                    } else {
                        ForEach(Array(mostWorn.prefix(10).enumerated()), id: \.element.id) { (idx, item) in
                            VStack(spacing: 0) {
                                HStack(spacing: metrics.value(14)) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: metrics.value(15), weight: .bold))
                                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.4))
                                        .frame(width: metrics.value(18))

                                    MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                                        .frame(width: metrics.value(56), height: metrics.value(76))

                                    VStack(alignment: .leading, spacing: metrics.value(3)) {
                                        Text(item.name)
                                            .font(.system(size: metrics.value(14), weight: .semibold))
                                            .foregroundStyle(ClosetTheme.textPrimary)
                                        Text(item.section.rawValue)
                                            .font(.system(size: metrics.value(12), weight: .medium))
                                            .foregroundStyle(ClosetTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("\(item.wearCount)")
                                            .font(.system(size: metrics.value(20), weight: .heavy))
                                            .foregroundStyle(ClosetTheme.indigo)
                                        Text("次穿着")
                                            .font(.system(size: metrics.value(11), weight: .medium))
                                            .foregroundStyle(ClosetTheme.textSecondary)
                                    }
                                }
                                .padding(.vertical, metrics.value(10))
                                if idx < min(mostWorn.count, 10) - 1 {
                                    Divider().overlay(ClosetTheme.line.opacity(0.35))
                                }
                            }
                        }
                    }
                }
            }

            if !idleItems.isEmpty {
                FrostedCard {
                    VStack(alignment: .leading, spacing: metrics.value(10)) {
                        Text("闲置提醒")
                            .font(.system(size: metrics.value(16), weight: .bold))
                            .foregroundStyle(ClosetTheme.textPrimary)
                        ForEach(Array(idleItems.prefix(5).enumerated()), id: \.element.id) { idx, item in
                            HStack(spacing: metrics.value(10)) {
                                Text("\(idx + 1)")
                                    .font(.system(size: metrics.value(13), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.5))
                                    .frame(width: metrics.value(18))
                                MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                                    .frame(width: metrics.value(42), height: metrics.value(56))
                                VStack(alignment: .leading, spacing: metrics.value(2)) {
                                    Text(item.name)
                                        .font(.system(size: metrics.value(13), weight: .semibold))
                                        .foregroundStyle(ClosetTheme.textPrimary)
                                    Text(idleDescription(for: item))
                                        .font(.system(size: metrics.value(11.5), weight: .medium))
                                        .foregroundStyle(ClosetTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func idleDescription(for item: ClosetItem) -> String {
        guard let lastWornDate = store.lastWornDate(for: item.id) else {
            return "加入后还没穿过"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "上次穿着 \(formatter.string(from: lastWornDate))"
    }
}

private struct WearBigStat: View {
    let value: String; let label: String; let color: Color; let metrics: LayoutMetrics
    var body: some View {
        VStack(spacing: metrics.value(5)) {
            Text(value).font(.system(size: metrics.value(36), weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: metrics.value(12), weight: .medium)).foregroundStyle(ClosetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AI Deep Analysis Sheet
private struct AIDeepAnalysisSheet: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    let metrics: LayoutMetrics
    @Environment(\.dismiss) private var dismiss

    private let sectionColors: [Color] = [
        Color(hue: 0.14, saturation: 0.3, brightness: 0.98),
        Color(hue: 0.58, saturation: 0.18, brightness: 0.97),
        Color(hue: 0.42, saturation: 0.2, brightness: 0.97),
        Color(hue: 0.71, saturation: 0.18, brightness: 0.97)
    ]
    private let sectionIcons = ["lightbulb", "arrow.up.right", "checkmark.circle", "star"]
    private let sectionIconColors: [Color] = [Color.orange, ClosetTheme.indigo, ClosetTheme.mint, ClosetTheme.rose]

    // Split the AI text into sections by "建议" markers
    private var sections: [(title: String, body: String, color: Color, icon: String, iconColor: Color)] {
        guard let text = viewModel.aiAnalysisText?.nilIfBlank else { return [] }
        var results: [(title: String, body: String, color: Color, icon: String, iconColor: Color)] = []

        // Add health analysis header
        results.append((title: "衣橱健康分析", body: "", color: sectionColors[0], icon: sectionIcons[0], iconColor: sectionIconColors[0]))

        // Split by numbered suggestions
        let parts = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var currentTitle = ""
        var currentBody: [String] = []
        var sectionIdx = 1
        for line in parts {
            if line.contains("建议") && (line.hasPrefix("建议") || line.contains("：") || line.contains(":")) {
                if !currentTitle.isEmpty {
                    let idx = (sectionIdx - 1) % sectionColors.count
                    results.append((title: currentTitle, body: currentBody.joined(separator: "\n"), color: sectionColors[idx], icon: sectionIcons[idx], iconColor: sectionIconColors[idx]))
                    sectionIdx += 1
                }
                currentTitle = line.trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        if !currentTitle.isEmpty {
            let idx = (sectionIdx - 1) % sectionColors.count
            results.append((title: currentTitle, body: currentBody.joined(separator: "\n"), color: sectionColors[idx], icon: sectionIcons[idx], iconColor: sectionIconColors[idx]))
        }
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule().fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5).padding(.top, 12).padding(.bottom, 8)

            // Sheet header
            HStack(spacing: metrics.value(12)) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.value(10))
                        .fill(ClosetTheme.accentGradient)
                        .frame(width: metrics.value(40), height: metrics.value(40))
                    Image(systemName: "sparkles")
                        .font(.system(size: metrics.value(18), weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 衣橱深度分析")
                        .font(.system(size: metrics.value(16), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    Text("基于您的实时衣橱数据生成")
                        .font(.system(size: metrics.value(12), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: metrics.value(14), weight: .semibold))
                        .foregroundStyle(ClosetTheme.textSecondary)
                        .padding(metrics.value(8))
                        .background(ClosetTheme.secondaryCard)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, metrics.value(20))
            .padding(.bottom, metrics.value(16))

            Divider()

            if let text = viewModel.aiAnalysisText?.nilIfBlank {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: metrics.value(12)) {
                        if sections.isEmpty {
                            // Fallback: show raw text
                            FrostedCard {
                                Text(text)
                                    .font(.system(size: metrics.value(14), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            ForEach(sections.indices, id: \.self) { idx in
                                let s = sections[idx]
                                VStack(alignment: .leading, spacing: metrics.value(10)) {
                                    HStack(spacing: metrics.value(8)) {
                                        Image(systemName: s.icon)
                                            .font(.system(size: metrics.value(14), weight: .bold))
                                            .foregroundStyle(s.iconColor)
                                        Text(s.title)
                                            .font(.system(size: metrics.value(15), weight: .bold))
                                            .foregroundStyle(ClosetTheme.textPrimary)
                                    }
                                    .padding(metrics.value(14))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(s.color)
                                    .clipShape(RoundedRectangle(cornerRadius: metrics.value(14)))

                                    if !s.body.isEmpty {
                                        Text(s.body)
                                            .font(.system(size: metrics.value(14), weight: .regular))
                                            .foregroundStyle(ClosetTheme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(metrics.value(14))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(s.color.opacity(0.5))
                                            .clipShape(RoundedRectangle(cornerRadius: metrics.value(14)))
                                    }
                                }
                            }
                        }
                    }
                    .padding(metrics.value(20))
                }
            } else {
                VStack(spacing: metrics.value(16)) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.3))
                    Text("还没有 AI 分析报告")
                        .font(.system(size: metrics.value(16), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.6))
                    Text("返回分析页点击「AI 分析」按钮生成报告")
                        .font(.system(size: metrics.value(13)))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.4))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(metrics.value(20))
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}


struct ProfileScreen: View {
    @ObservedObject var store: ClosetStore
    @ObservedObject var profileViewModel: ProfileViewModel
    @EnvironmentObject private var appViewModel: AppViewModel
    let metrics: LayoutMetrics

    @State private var isEditingProfile = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupDocument = LocalClosetBackupDocument(
        payload: LocalClosetBackupPayload(
            snapshot: MockClosetDashboard.sampleSnapshot,
            images: [:],
            exportedAt: .now
        )
    )
    @State private var localMaintenanceMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: metrics.value(12)) {
                PageHeader(
                    title: "身体档案",
                    badge: "PROFILE",
                    titleAccessory: { EmptyView() },
                    metrics: metrics,
                    actions: {
                        HStack(spacing: metrics.value(8)) {
                            HeaderCapsuleButton(title: "备份", icon: "square.and.arrow.up", metrics: metrics)
                                .onTapGesture {
                                    backupDocument = store.makeBackupDocument()
                                    isExportingBackup = true
                                }
                            HeaderCapsuleButton(title: "编辑", icon: "square.and.pencil", metrics: metrics)
                        }
                        .onTapGesture {
                            isEditingProfile = true
                        }
                    }
                )

                // 用户卡片
                FrostedCard(padding: metrics.value(18)) {
                    VStack(alignment: .leading, spacing: metrics.value(14)) {
                        // 头像 + 基本信息
                        HStack(alignment: .center, spacing: metrics.value(12)) {
                            ZStack {
                                Circle()
                                    .fill(ClosetTheme.roseGradient)
                                    .frame(width: metrics.value(64), height: metrics.value(64))
                                Image(systemName: "person.fill")
                                    .font(.system(size: metrics.value(28), weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                            .shadow(color: ClosetTheme.rose.opacity(0.25), radius: 10, y: 5)

                            VStack(alignment: .leading, spacing: metrics.value(4)) {
                                HStack(spacing: metrics.value(5)) {
                                    Text(profileDisplayName)
                                        .font(.system(size: metrics.value(17), weight: .bold))
                                        .foregroundStyle(ClosetTheme.textPrimary)
                                }
                                Text(profileSubtitle)
                                    .font(.system(size: metrics.value(11.5), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
                            }

                            Spacer()

                            Button(action: handleSessionButtonTapped) {
                                Text(sessionButtonTitle)
                            }
                            .font(.system(size: metrics.value(11.5), weight: .semibold))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.6))
                            .padding(.horizontal, metrics.value(8))
                            .padding(.vertical, metrics.value(5))
                            .background(ClosetTheme.secondaryCard)
                            .clipShape(Capsule())
                        }

                        Divider()
                            .overlay(ClosetTheme.line)

                        // 身体数据
                        VStack(spacing: metrics.value(10)) {
                            FormMetricRow(icon: "ruler", iconColor: ClosetTheme.indigo, title: "身高", value: profileHeightText, unit: "cm", metrics: metrics)
                            FormMetricRow(icon: "scalemass", iconColor: ClosetTheme.rose, title: "体重", value: profileWeightText, unit: "kg", metrics: metrics)
                        }

                        Divider()
                            .overlay(ClosetTheme.line)

                        // 身形照片
                        VStack(alignment: .leading, spacing: metrics.value(10)) {
                            HStack {
                                Text("身形照片")
                                    .font(.system(size: metrics.value(14), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textPrimary)
                                Spacer()
                                Text("+ 上传")
                                    .font(.system(size: metrics.value(11.5), weight: .semibold))
                                    .foregroundStyle(ClosetTheme.indigo)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isEditingProfile = true
                            }

                            HStack(spacing: metrics.value(8)) {
                                ForEach(displayBodyPhotos) { photo in
                                    BodyPhotoCard(photo: photo, metrics: metrics)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            isEditingProfile = true
                                        }
                                }
                            }
                        }

                        if let description = profileDescription {
                            Divider()
                                .overlay(ClosetTheme.line)

                            VStack(alignment: .leading, spacing: metrics.value(8)) {
                                Text("风格描述")
                                    .font(.system(size: metrics.value(14), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textPrimary)
                                Text(description)
                                    .font(.system(size: metrics.value(13), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // 版本信息卡片
                FrostedCard(padding: metrics.value(16)) {
                    VStack(alignment: .leading, spacing: metrics.value(12)) {
                        HStack(spacing: metrics.value(10)) {
                            ZStack {
                                Circle()
                                    .fill(ClosetTheme.secondaryCard)
                                    .frame(width: metrics.value(36), height: metrics.value(36))
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: metrics.value(18)))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: metrics.value(2)) {
                                Text("Closet v1.0.0")
                                    .font(.system(size: metrics.value(14), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textPrimary)
                                Text("构建于 2026/03/06")
                                    .font(.system(size: metrics.value(11.5), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
                            }

                            Spacer()
                        }

                        HStack(spacing: metrics.value(10)) {
                            HeaderCapsuleButton(title: "恢复", icon: "square.and.arrow.down", metrics: metrics)
                                .onTapGesture {
                                    isImportingBackup = true
                                }
                            HeaderCapsuleButton(title: "清理缓存", icon: "trash", metrics: metrics)
                                .onTapGesture {
                                    let removed = store.cleanupUnusedAssets()
                                    localMaintenanceMessage = removed > 0 ? "已清理 \(removed) 张未引用图片" : "当前没有可清理的本地图片"
                                }
                        }

                        if let localMaintenanceMessage {
                            Text(localMaintenanceMessage)
                                .font(.system(size: metrics.value(12), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.pageTopSpacing)
            .padding(.bottom, metrics.value(20))
        }
        .sheet(isPresented: $isEditingProfile) {
            if appViewModel.authState == .signedIn {
                RemoteProfileEditorSheet(viewModel: profileViewModel)
            } else {
                ProfileEditorSheet(store: store, metrics: metrics)
            }
        }
        .task {
            guard appViewModel.authState == .signedIn else { return }
            guard profileViewModel.profile == nil else { return }
            await profileViewModel.loadProfile()
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "closet-backup"
        ) { result in
            switch result {
            case .success:
                localMaintenanceMessage = "本地备份已导出"
            case .failure(let error):
                localMaintenanceMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                guard url.startAccessingSecurityScopedResource() else {
                    localMaintenanceMessage = "无法访问所选备份文件"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let payload = try decoder.decode(LocalClosetBackupPayload.self, from: data)
                store.importBackup(LocalClosetBackupDocument(payload: payload))
                localMaintenanceMessage = "本地备份已恢复"
            } catch {
                localMaintenanceMessage = "恢复失败：\(error.localizedDescription)"
            }
        }
    }

    private var profileDisplayName: String {
        profileNameText
    }

    private var profileSubtitle: String {
        "纯本地模式，所有资料和图片仅保存在本机"
    }

    private var sessionButtonTitle: String {
        "本地模式"
    }

    private func handleSessionButtonTapped() {
    }

    private var usingRemoteProfile: Bool {
        appViewModel.authState == .signedIn
    }

    private var profileNameText: String {
        if let remoteName = profileViewModel.profile?.name.nilIfBlank, usingRemoteProfile {
            return remoteName
        }
        return appViewModel.currentUser?.username ?? store.profile.name
    }

    private var profileHeightText: String {
        if let remoteHeight = profileViewModel.profile?.heightCm, usingRemoteProfile {
            return String(Int(remoteHeight.rounded()))
        }
        return "\(store.profile.heightCm)"
    }

    private var profileWeightText: String {
        if let remoteWeight = profileViewModel.profile?.weightKg, usingRemoteProfile {
            return String(Int(remoteWeight.rounded()))
        }
        return "\(store.profile.weightKg)"
    }

    private var profileDescription: String? {
        guard usingRemoteProfile else { return nil }
        return profileViewModel.profile?.description?.nilIfBlank
    }

    private var displayBodyPhotos: [ProfilePhotoDisplay] {
        if usingRemoteProfile, let profile = profileViewModel.profile {
            return [
                ProfilePhotoDisplay(title: "正面", symbol: "figure.stand", remoteURLString: profile.photoFront),
                ProfilePhotoDisplay(title: "侧面", symbol: "figure.turn.right", remoteURLString: profile.photoSide),
                ProfilePhotoDisplay(title: "背面", symbol: "figure.stand.line.dotted.figure.stand", remoteURLString: profile.photoBack)
            ]
        }

        return store.profile.bodyPhotos.map {
            ProfilePhotoDisplay(title: $0.title, symbol: $0.symbol, localFileName: $0.imageFileName)
        }
    }
}


struct PageHeader<TitleAccessory: View, Actions: View>: View {
    let title: String
    let badge: String
    @ViewBuilder let titleAccessory: TitleAccessory
    let metrics: LayoutMetrics
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center, spacing: PageHeaderStyle.spacing(for: metrics)) {
                Text(title)
                    .font(.system(size: PageHeaderStyle.titleSize(for: metrics), weight: .heavy, design: .default))
                    .foregroundStyle(ClosetTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: PageHeaderStyle.badgeSize(for: metrics), weight: .black, design: .rounded))
                        .foregroundStyle(ClosetTheme.rose)
                        .padding(.horizontal, PageHeaderStyle.badgeHorizontalPadding(for: metrics))
                        .padding(.vertical, PageHeaderStyle.badgeVerticalPadding(for: metrics))
                        .background(Color(red: 1, green: 0.88, blue: 0.9))
                        .clipShape(RoundedRectangle(cornerRadius: PageHeaderStyle.badgeCornerRadius(for: metrics)))
                }
                titleAccessory
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: metrics.value(10))
            actions
        }
        .frame(minHeight: PageHeaderStyle.minHeight(for: metrics), alignment: .center)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(10)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.value(16), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
            TextField(placeholder, text: $text)
                .font(.system(size: metrics.value(16), weight: .medium))
                .foregroundStyle(ClosetTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Spacer()
        }
        .padding(.horizontal, metrics.value(14))
        .frame(height: metrics.value(46))
        .background(ClosetTheme.secondaryCard)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(18)))
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let metrics: LayoutMetrics

    var body: some View {
        Text(title)
            .font(.system(size: metrics.value(13), weight: .bold))
            .foregroundStyle(selected ? .white : ClosetTheme.textSecondary.opacity(0.95))
            .padding(.horizontal, metrics.value(14))
            .frame(height: metrics.value(38))
            .background(
                selected
                    ? AnyShapeStyle(ClosetTheme.roseGradient)
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.82), ClosetTheme.secondaryCard.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? .white.opacity(0.28) : ClosetTheme.line.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: selected ? ClosetTheme.rose.opacity(0.16) : ClosetTheme.tabShadow.opacity(0.08), radius: 8, y: 4)
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let countText: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(8)) {
            Text(title)
                .font(.system(size: metrics.value(18), weight: .heavy))
                .foregroundStyle(ClosetTheme.textPrimary.opacity(0.88))

            Text(countText)
                .font(.system(size: metrics.value(11), weight: .bold, design: .rounded))
                .foregroundStyle(ClosetTheme.textSecondary)
                .padding(.horizontal, metrics.value(8))
                .frame(height: metrics.value(24))
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.68))
                )
                .overlay(
                    Capsule()
                        .stroke(ClosetTheme.line.opacity(0.55), lineWidth: 1)
                )
        }
    }
}

struct HeaderCapsuleButton: View {
    let title: String
    let icon: String
    var filled: Bool = false
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: PageHeaderStyle.actionSpacing(for: metrics)) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: PageHeaderStyle.actionFontSize(for: metrics), weight: .bold))
        .foregroundStyle(filled ? .white : ClosetTheme.textSecondary)
        .padding(.horizontal, PageHeaderStyle.actionHorizontalPadding(for: metrics))
        .frame(height: PageHeaderStyle.actionHeight(for: metrics))
        .background(filled ? ClosetTheme.slate : ClosetTheme.secondaryCard)
        .clipShape(RoundedRectangle(cornerRadius: PageHeaderStyle.actionCornerRadius(for: metrics)))
    }
}

struct CircularGradientButton: View {
    let icon: String
    let metrics: LayoutMetrics

    var body: some View {
        Circle()
            .fill(ClosetTheme.roseGradient)
            .frame(width: metrics.value(54), height: metrics.value(54))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: metrics.value(22), weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: ClosetTheme.rose.opacity(0.25), radius: 18, y: 10)
    }
}

private struct FloatingAccentActionButton: View {
    let icon: String
    let isExpanded: Bool
    let metrics: LayoutMetrics

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ClosetTheme.rose.opacity(isExpanded ? 0.34 : 0.18),
                            ClosetTheme.violet.opacity(isExpanded ? 0.14 : 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: metrics.value(8),
                        endRadius: metrics.value(36)
                    )
                )
                .frame(width: metrics.value(80), height: metrics.value(80))
                .blur(radius: metrics.value(4))

            Circle()
                .fill(ClosetTheme.roseGradient)
                .frame(width: metrics.value(54), height: metrics.value(54))
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: metrics.value(21), weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isExpanded && icon == "plus" ? 45 : 0))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.65), lineWidth: 1)
                )
                .shadow(color: ClosetTheme.rose.opacity(isExpanded ? 0.34 : 0.24), radius: isExpanded ? 22 : 18, y: isExpanded ? 12 : 10)
                .scaleEffect(isExpanded ? 1.04 : 1)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isExpanded)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(8)) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: metrics.value(16), weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.value(58))
        .background(ClosetTheme.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(20)))
        .shadow(color: ClosetTheme.indigo.opacity(0.18), radius: 16, y: 8)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(10)) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: metrics.value(18), weight: .bold))
        .foregroundStyle(ClosetTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.value(72))
        .background(ClosetTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(24)))
    }
}

struct ToggleTile: View {
    let title: String
    let icon: String
    let selected: Bool
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(7)) {
            Image(systemName: icon)
                .font(.system(size: metrics.value(13), weight: .semibold))
            Text(title)
        }
        .font(.system(size: metrics.value(13.5), weight: .bold))
        .foregroundStyle(selected ? .white : ClosetTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.value(44))
        .background(selected ? AnyShapeStyle(ClosetTheme.accentGradient) : AnyShapeStyle(ClosetTheme.secondaryCard))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(15)))
        .shadow(color: selected ? ClosetTheme.indigo.opacity(0.12) : .clear, radius: 10, y: 4)
    }
}

struct AIRecommendationPanel: View {
    @Binding var prompt: String
    let weather: WeatherSnapshot
    let onGenerate: () -> Void
    let metrics: LayoutMetrics

    var body: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: metrics.value(14)) {
                Label("今日天气", systemImage: "cloud.sun")
                    .font(.system(size: metrics.value(17), weight: .bold))
                    .foregroundStyle(ClosetTheme.textSecondary)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.92, green: 0.95, blue: 1))
                    .frame(height: metrics.value(96))
                    .overlay(
                        HStack {
                            HStack(spacing: metrics.value(10)) {
                                Image(systemName: "cloud.sun")
                                    .font(.system(size: metrics.value(20), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.75))
                                    .font(.system(size: metrics.value(28)))
                                VStack(alignment: .leading, spacing: metrics.value(4)) {
                                    Text("\(weather.temperature)°C \(weather.condition)")
                                        .font(.system(size: metrics.value(18), weight: .bold))
                                        .foregroundStyle(ClosetTheme.textPrimary)
                                    Text("\(weather.location)  ·  \(weather.humidity)%  ·  体感\(weather.feelsLike)°C")
                                        .font(.system(size: metrics.value(13), weight: .medium))
                                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.75))
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: metrics.value(18), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary.opacity(0.65))
                        }
                        .padding(.horizontal, metrics.value(18))
                    )

                VStack(alignment: .leading, spacing: metrics.value(8)) {
                    Label("搭配要求（可选）", systemImage: "sparkles")
                        .font(.system(size: metrics.value(17), weight: .bold))
                        .foregroundStyle(ClosetTheme.textSecondary)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ClosetTheme.line, lineWidth: 1.5)
                            .frame(height: metrics.value(118))

                        if prompt.isEmpty {
                            Text("例如：想要一套适合春天约会的清新风格搭配...")
                                .font(.system(size: metrics.value(14), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary.opacity(0.45))
                                .padding(metrics.value(18))
                        }

                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: metrics.value(14), weight: .medium))
                            .padding(.horizontal, metrics.value(14))
                            .padding(.vertical, metrics.value(10))
                            .frame(height: metrics.value(118))
                            .background(Color.clear)
                    }

                    Text("输入你的想法，AI会根据衣橱智能推荐")
                        .font(.system(size: metrics.value(12.5), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.55))
                }

                PrimaryActionButton(title: "获取搭配建议", icon: "sparkles", metrics: metrics)
                    .onTapGesture(perform: onGenerate)
            }
        }
    }
}

private struct OutfitCanvasBoard: View {
    let items: [ClosetItem]
    @Binding var layouts: [OutfitItemLayout]
    let metrics: LayoutMetrics
    var isEditable: Bool = true
    var showsBackdrop: Bool = true
    var boardAspectRatio: CGFloat = 3.0 / 4.4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                if showsBackdrop {
                    RoundedRectangle(cornerRadius: metrics.value(26))
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.97, green: 0.98, blue: 1), Color(red: 0.93, green: 0.95, blue: 0.99)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    RoundedRectangle(cornerRadius: metrics.value(26))
                        .stroke(.white.opacity(0.78), lineWidth: 1)
                }

                ForEach(orderedItems) { item in
                    let layout = layout(for: item.id)
                    OutfitCanvasItem(
                        item: item,
                        layout: layout,
                        boardSize: size,
                        isEditable: isEditable,
                        metrics: metrics,
                        onFocus: {
                            bringToFront(item.id)
                        }
                    ) { nextLayout in
                        updateLayout(for: item.id, nextLayout: nextLayout, in: size)
                    }
                }
            }
        }
        .aspectRatio(boardAspectRatio, contentMode: .fit)
    }

    private var orderedItems: [ClosetItem] {
        let orderMap = Dictionary(uniqueKeysWithValues: layouts.enumerated().map { ($1.itemID, $0) })
        return items.sorted { lhs, rhs in
            (orderMap[lhs.id] ?? 0) < (orderMap[rhs.id] ?? 0)
        }
    }

    private func layout(for itemID: UUID) -> OutfitItemLayout {
        layouts.first(where: { $0.itemID == itemID })
        ?? OutfitItemLayout(itemID: itemID, x: 0.5, y: 0.5)
    }

    private func updateLayout(for itemID: UUID, nextLayout: OutfitItemLayout, in size: CGSize) {
        let clampedX = min(max(nextLayout.x / max(size.width, 1), 0.14), 0.86)
        let clampedY = min(max(nextLayout.y / max(size.height, 1), 0.1), 0.9)
        guard let index = layouts.firstIndex(where: { $0.itemID == itemID }) else { return }
        layouts[index].x = clampedX
        layouts[index].y = clampedY
        layouts[index].scale = min(max(nextLayout.scale, 0.65), 1.75)
        layouts[index].rotation = nextLayout.rotation
    }

    private func bringToFront(_ itemID: UUID) {
        guard isEditable, let index = layouts.firstIndex(where: { $0.itemID == itemID }) else { return }
        let layout = layouts.remove(at: index)
        layouts.append(layout)
    }
}

private struct OutfitCanvasItem: View {
    let item: ClosetItem
    let layout: OutfitItemLayout
    let boardSize: CGSize
    let isEditable: Bool
    let metrics: LayoutMetrics
    let onFocus: () -> Void
    let onChange: (OutfitItemLayout) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var gestureScale: CGFloat = 1
    @State private var gestureRotation: Angle = .zero

    private var itemSize: CGSize {
        let baseRatio = isEditable ? 0.28 : 0.42
        return CGSize(width: boardSize.width * baseRatio * layout.scale, height: boardSize.height * baseRatio * layout.scale)
    }

    private var baseCenter: CGPoint {
        CGPoint(x: boardSize.width * layout.x, y: boardSize.height * layout.y)
    }

    var body: some View {
        MiniGarmentCard(
            symbol: item.symbol,
            gradientName: item.gradientName,
            imageFileName: item.imageFileName,
            metrics: metrics,
            displayStyle: .cutout
        )
        .frame(width: itemSize.width, height: itemSize.height)
        .overlay(alignment: .topTrailing) {
            if isEditable {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: metrics.value(10), weight: .bold))
                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
                    .padding(metrics.value(6))
            }
        }
        .position(
            x: baseCenter.x + dragOffset.width,
            y: baseCenter.y + dragOffset.height
        )
        .rotationEffect(.degrees(layout.rotation) + gestureRotation)
        .scaleEffect(gestureScale)
        .onTapGesture {
            guard isEditable else { return }
            onFocus()
        }
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard isEditable else { return }
                        onFocus()
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard isEditable else { return }
                        let nextLayout = OutfitItemLayout(
                            itemID: item.id,
                            x: baseCenter.x + value.translation.width,
                            y: baseCenter.y + value.translation.height,
                            scale: layout.scale * Double(gestureScale),
                            rotation: layout.rotation + gestureRotation.degrees
                        )
                        dragOffset = .zero
                        gestureScale = 1
                        gestureRotation = .zero
                        onChange(nextLayout)
                    },
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard isEditable else { return }
                            gestureScale = value
                        }
                        .onEnded { value in
                            guard isEditable else { return }
                            let nextLayout = OutfitItemLayout(
                                itemID: item.id,
                                x: baseCenter.x,
                                y: baseCenter.y,
                                scale: layout.scale * Double(value),
                                rotation: layout.rotation + gestureRotation.degrees
                            )
                            gestureScale = 1
                            onChange(nextLayout)
                        },
                    RotationGesture()
                        .onChanged { value in
                            guard isEditable else { return }
                            gestureRotation = value
                        }
                        .onEnded { value in
                            guard isEditable else { return }
                            let nextLayout = OutfitItemLayout(
                                itemID: item.id,
                                x: baseCenter.x,
                                y: baseCenter.y,
                                scale: layout.scale * Double(gestureScale),
                                rotation: layout.rotation + value.degrees
                            )
                            gestureRotation = .zero
                            onChange(nextLayout)
                        }
                )
            )
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: layout)
    }
}

struct ManualSelectionPanel: View {
    @ObservedObject var store: ClosetStore
    @Binding var selectedItemIDs: Set<UUID>
    @Binding var itemLayouts: [OutfitItemLayout]
    let onSave: () -> Void
    let metrics: LayoutMetrics

    private var itemsBySection: [WardrobeSection: [ClosetItem]] {
        Dictionary(grouping: store.activeWardrobeItems, by: \.section)
    }

    private var selectedItems: [ClosetItem] {
        store.activeWardrobeItems.filter { selectedItemIDs.contains($0.id) }
    }

    private var canSave: Bool {
        !selectedItemIDs.isEmpty
    }

    var body: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: metrics.value(18)) {
                Divider().overlay(ClosetTheme.line)

                ForEach(WardrobeSection.allCases) { section in
                    VStack(alignment: .leading, spacing: metrics.value(10)) {
                        Text(section.rawValue)
                            .font(.system(size: metrics.value(22), weight: .bold))
                            .foregroundStyle(ClosetTheme.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: metrics.value(10)) {
                                ForEach(itemsBySection[section] ?? []) { item in
                                    SelectableGarmentCard(
                                        item: item,
                                        isSelected: selectedItemIDs.contains(item.id),
                                        metrics: metrics
                                    )
                                    .onTapGesture {
                                        if selectedItemIDs.contains(item.id) {
                                            selectedItemIDs.remove(item.id)
                                            itemLayouts.removeAll { $0.itemID == item.id }
                                        } else {
                                            selectedItemIDs = selectedItemIDs.filter { existingID in
                                                guard let existingItem = store.activeWardrobeItems.first(where: { $0.id == existingID }) else { return false }
                                                return existingItem.section != section
                                            }
                                            itemLayouts.removeAll { layout in
                                                !selectedItemIDs.contains(layout.itemID)
                                            }
                                            selectedItemIDs.insert(item.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                Button(action: onSave) {
                    PrimaryActionButton(title: "保存手动搭配", icon: "bookmark", metrics: metrics)
                        .opacity(canSave ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
    }
}

struct WardrobeItemCard: View {
    let item: ClothingItem
    let metrics: LayoutMetrics

    var body: some View {
        GeometryReader { proxy in
            let cardSize = proxy.size
            let visualHeight = cardSize.height * 0.7

            VStack(alignment: .leading, spacing: 0) {
                RemoteGarmentCard(item: item, metrics: metrics)
                    .frame(height: visualHeight)

                VStack(alignment: .leading, spacing: metrics.value(4)) {
                    Text(item.name)
                        .font(.system(size: metrics.value(11.5), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, metrics.value(8))
                .padding(.top, metrics.value(8))
                .padding(.bottom, metrics.value(10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ClosetTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(18)))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(18))
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: ClosetTheme.tabShadow.opacity(0.8), radius: 10, y: 5)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }
}

struct LocalWardrobeItemCard: View {
    let item: ClosetItem
    let metrics: LayoutMetrics
    let isDeleteArmed: Bool
    let showingArchivedStyle: Bool
    let onActionRevealTap: () -> Void
    let onDeleteRequest: () -> Void
    let onToggleArchive: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: metrics.value(8)) {
                ZStack(alignment: .top) {
                    MiniGarmentCard(
                        symbol: item.symbol,
                        gradientName: item.gradientName,
                        imageFileName: item.imageFileName,
                        metrics: metrics
                    )

                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(height: proxy.size.height * 0.26)
                            .onTapGesture {
                                onActionRevealTap()
                            }
                        Spacer(minLength: 0)
                    }

                    if isDeleteArmed {
                        HStack(spacing: metrics.value(8)) {
                            CardOverlayActionButton(
                                icon: showingArchivedStyle ? "tray.and.arrow.up" : "archivebox",
                                tint: showingArchivedStyle ? ClosetTheme.mint : ClosetTheme.indigo,
                                action: onToggleArchive
                            )
                            CardOverlayActionButton(
                                icon: "trash",
                                tint: ClosetTheme.rose,
                                action: onDeleteRequest
                            )
                        }
                        .padding(.top, metrics.value(10))
                    } else {
                        CardTopHandle(metrics: metrics)
                            .padding(.top, metrics.value(10))
                    }
                }

                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text(item.name)
                        .font(.system(size: metrics.value(12), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .lineLimit(2)
                }
                .padding(.horizontal, metrics.value(8))
                .padding(.bottom, metrics.value(10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ClosetTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: ClosetTheme.tabShadow.opacity(0.8), radius: 10, y: 5)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }
}

private struct CardOverlayActionButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint)
                .clipShape(Circle())
                .shadow(color: tint.opacity(0.24), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct RemoteGarmentCard: View {
    let item: ClothingItem
    let metrics: LayoutMetrics

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.value(18))
            .fill(item.gradient)
            .overlay {
                if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(metrics.value(8))
                        default:
                            Image(systemName: item.category.systemImageName)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(ClosetTheme.textSecondary.opacity(0.86))
                                .padding(metrics.value(28))
                        }
                    }
                } else {
                    Image(systemName: item.category.systemImageName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.86))
                        .padding(metrics.value(28))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(18))
                    .stroke(.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: ClosetTheme.slate.opacity(0.08), radius: 18, y: 10)
    }
}

struct SelectableGarmentCard: View {
    let item: ClosetItem
    let isSelected: Bool
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(8)) {
            MiniGarmentCard(symbol: item.symbol, gradientName: item.gradientName, imageFileName: item.imageFileName, metrics: metrics)
                .frame(width: metrics.value(118), height: metrics.value(152))

            Text(item.name)
                .font(.system(size: metrics.value(13), weight: .bold))
                .foregroundStyle(ClosetTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(metrics.value(8))
        .background(ClosetTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(20)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(20))
                .stroke(isSelected ? ClosetTheme.indigo : .white.opacity(0.75), lineWidth: isSelected ? 2.5 : 1)
        )
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let metrics: LayoutMetrics

    var body: some View {
        FrostedCard {
            VStack(spacing: metrics.value(10)) {
                Image(systemName: icon)
                    .font(.system(size: metrics.value(28), weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.5))
                Text(title)
                    .font(.system(size: metrics.value(16), weight: .bold))
                    .foregroundStyle(ClosetTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: metrics.value(14), weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct MiniGarmentCard: View {
    enum DisplayStyle {
        case card
        case cutout
    }

    let symbol: String
    let gradientName: String
    let imageFileName: String?
    let metrics: LayoutMetrics
    var displayStyle: DisplayStyle = .card

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.95, green: 0.96, blue: 0.98), .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Group {
            switch displayStyle {
            case .card:
                RoundedRectangle(cornerRadius: metrics.value(18))
                    .fill(gradient)
                    .overlay {
                        garmentContent(innerPadding: metrics.value(8), placeholderPadding: metrics.value(28))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.value(18))
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: ClosetTheme.slate.opacity(0.08), radius: 18, y: 10)
            case .cutout:
                garmentContent(innerPadding: 0, placeholderPadding: metrics.value(18))
                    .padding(metrics.value(2))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }
        }
    }

    @ViewBuilder
    private func garmentContent(innerPadding: CGFloat, placeholderPadding: CGFloat) -> some View {
        if let image = LocalImageStore.shared.loadImage(named: imageFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(innerPadding)
        } else {
            VStack {
                Spacer(minLength: metrics.value(16))
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.86))
                    .padding(placeholderPadding)
                    .shadow(color: .white.opacity(0.8), radius: 22, y: 8)
                Spacer()
            }
        }
    }
}

struct OutfitLookCard: View {
    let look: OutfitPreview
    let linkedItems: [ClosetItem]
    let metrics: LayoutMetrics
    let isDeleteArmed: Bool
    let onDeleteControlTap: () -> Void
    let onDeleteRequest: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = proxy.size.height * 0.8

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    OutfitPreviewThumbnail(
                        look: look,
                        linkedItems: linkedItems,
                        metrics: metrics,
                        placeholderLabel: "搭配底稿",
                        maxWidth: proxy.size.width,
                        integrated: true
                    )
                    .frame(height: visualHeight)
                    .allowsHitTesting(false)

                    RevealDeleteControl(
                        isArmed: isDeleteArmed,
                        metrics: metrics,
                        onArm: onDeleteControlTap,
                        onDelete: onDeleteRequest
                    )
                    .padding(metrics.value(8))
                }

                VStack(alignment: .leading, spacing: metrics.value(2)) {
                    Text(look.title)
                        .font(.system(size: metrics.value(12), weight: .bold))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .lineLimit(2)
                }
                .padding(.horizontal, metrics.value(8))
                .padding(.top, metrics.value(8))
                .padding(.bottom, metrics.value(10))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ClosetTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: ClosetTheme.tabShadow.opacity(0.8), radius: 10, y: 5)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .contentShape(Rectangle())
    }
}

private struct CardTopHandle: View {
    let metrics: LayoutMetrics

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: metrics.value(12), weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, metrics.value(10))
            .padding(.vertical, metrics.value(7))
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }
}

private struct OutfitPreviewThumbnail: View {
    let look: OutfitPreview
    let linkedItems: [ClosetItem]
    let metrics: LayoutMetrics
    let placeholderLabel: String
    let maxWidth: CGFloat
    var integrated: Bool = false

    var body: some View {
        ZStack {
            if !integrated {
                RoundedRectangle(cornerRadius: metrics.value(26))
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.95, blue: 0.99), Color(red: 0.97, green: 0.98, blue: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            if !linkedItems.isEmpty {
                OutfitCanvasBoard(
                    items: linkedItems,
                    layouts: .constant(normalizedLayouts),
                    metrics: metrics,
                    isEditable: false,
                    showsBackdrop: !integrated,
                    boardAspectRatio: 9.0 / 16.0
                )
                .padding(metrics.value(integrated ? 0 : 2))
            } else {
                VStack(spacing: metrics.value(8)) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: metrics.value(28), weight: .light))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.42))
                    Text(placeholderLabel)
                        .font(.system(size: metrics.value(10.5), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.42))
                        .multilineTextAlignment(.center)
                }
                .padding(metrics.value(10))
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxWidth: maxWidth)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(18), style: .continuous)
                .stroke(integrated ? .clear : .white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: ClosetTheme.tabShadow.opacity(integrated ? 0 : 0.8), radius: 10, y: 5)
        .frame(maxWidth: .infinity)
    }

    private var normalizedLayouts: [OutfitItemLayout] {
        if !look.itemLayouts.isEmpty { return look.itemLayouts }
        return linkedItems.enumerated().map { index, item in
            switch item.section {
            case .top:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.19, scale: integrated ? 1.12 : 1.0, rotation: 0)
            case .bottom:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.54, scale: integrated ? 1.04 : 0.94, rotation: 0)
            case .dress:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.4, scale: integrated ? 1.16 : 1.04, rotation: 0)
            case .shoes:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.84, scale: integrated ? 0.98 : 0.86, rotation: 0)
            case .uncategorized:
                return OutfitItemLayout(itemID: item.id, x: index.isMultiple(of: 2) ? 0.32 : 0.68, y: 0.55, scale: integrated ? 0.96 : 0.84, rotation: 0)
            }
        }
    }
}

private struct RevealDeleteControl: View {
    let isArmed: Bool
    let metrics: LayoutMetrics
    let onArm: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if isArmed {
                Button(action: onDelete) {
                    HStack(spacing: metrics.value(5)) {
                        Image(systemName: "trash.fill")
                        Text("删除")
                    }
                    .font(.system(size: metrics.value(11), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, metrics.value(10))
                    .frame(height: metrics.value(30))
                    .background(
                        Capsule()
                            .fill(ClosetTheme.roseGradient)
                    )
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.75), lineWidth: 1)
                    )
                    .shadow(color: ClosetTheme.rose.opacity(0.22), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onArm) {
                    CardTopHandle(metrics: metrics)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isArmed)
    }
}

struct OutfitDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClosetStore
    let look: OutfitPreview
    let metrics: LayoutMetrics

    @State private var isEditing = false

    private var latestLook: OutfitPreview {
        store.savedLooks.first(where: { $0.id == look.id }) ?? look
    }

    private var activeItemMap: [UUID: ClosetItem] {
        Dictionary(uniqueKeysWithValues: store.activeWardrobeItems.map { ($0.id, $0) })
    }

    private var linkedItems: [ClosetItem] {
        latestLook.itemIDs.compactMap { activeItemMap[$0] }
    }

    private var detailImageWidth: CGFloat {
        min(metrics.contentWidth - metrics.value(32), metrics.value(250))
    }

    private var resolvedLayouts: [OutfitItemLayout] {
        if !latestLook.itemLayouts.isEmpty {
            return latestLook.itemLayouts
        }

        return linkedItems.enumerated().map { index, item in
            switch item.section {
            case .top:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.2, scale: 1.02, rotation: 0)
            case .bottom:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.53, scale: 0.98, rotation: 0)
            case .dress:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.42, scale: 1.05, rotation: 0)
            case .shoes:
                return OutfitItemLayout(itemID: item.id, x: 0.5, y: 0.8, scale: 0.92, rotation: 0)
            case .uncategorized:
                return OutfitItemLayout(itemID: item.id, x: index % 2 == 0 ? 0.3 : 0.7, y: 0.5, scale: 0.92, rotation: 0)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.value(14)) {
                    VStack(alignment: .leading, spacing: metrics.value(4)) {
                        Text(latestLook.title)
                            .font(.system(size: metrics.value(24), weight: .heavy))
                            .foregroundStyle(ClosetTheme.textPrimary)
                            .padding(.horizontal, metrics.horizontalPadding)
                    }

                    if !linkedItems.isEmpty {
                        OutfitCanvasBoard(
                            items: linkedItems,
                            layouts: .constant(resolvedLayouts),
                            metrics: metrics,
                            isEditable: false
                        )
                        .frame(maxWidth: min(metrics.contentWidth * 0.9, metrics.value(320)))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, metrics.horizontalPadding)
                    }

                    if !linkedItems.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: metrics.value(10)) {
                                ForEach(linkedItems) { item in
                                    VStack(alignment: .leading, spacing: metrics.value(6)) {
                                        MiniGarmentCard(
                                            symbol: item.symbol,
                                            gradientName: item.gradientName,
                                            imageFileName: item.imageFileName,
                                            metrics: metrics
                                        )
                                        .frame(width: metrics.value(64), height: metrics.value(84))

                                        Text(item.name)
                                            .font(.system(size: metrics.value(10.5), weight: .semibold))
                                            .foregroundStyle(ClosetTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: metrics.value(64), alignment: .leading)
                                }
                            }
                            .padding(.horizontal, metrics.horizontalPadding)
                        }
                    }

                    FrostedCard(padding: metrics.value(18)) {
                        VStack(alignment: .leading, spacing: metrics.value(8)) {
                            Text("AI 搭配解读")
                                .font(.system(size: metrics.value(15), weight: .bold))
                                .foregroundStyle(ClosetTheme.textPrimary)
                            Text("这里预留给后续的 AI 搭配说明、风格建议和场景化文案。")
                                .font(.system(size: metrics.value(13), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary.opacity(0.76))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear
                                .frame(height: metrics.value(28))
                        }
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                }
                .padding(.top, metrics.value(4))
                .padding(.bottom, metrics.value(10))
            }
            .navigationTitle("搭配详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: metrics.value(16), weight: .semibold))
                            .foregroundStyle(ClosetTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") {
                        isEditing = true
                    }
                    .font(.system(size: metrics.value(14), weight: .semibold))
                }
            }
            .sheet(isPresented: $isEditing) {
                OutfitEditSheet(store: store, look: latestLook, metrics: metrics)
            }
        }
    }
}

// MARK: - Outfit Edit Sheet
struct OutfitEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClosetStore
    let look: OutfitPreview
    let metrics: LayoutMetrics

    @State private var draft = OutfitDraft()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    if !draft.itemIDs.isEmpty {
                        VStack(alignment: .leading, spacing: metrics.value(10)) {
                            HStack {
                                Text("拖拽底稿")
                                    .font(.system(size: metrics.value(16), weight: .bold))
                                    .foregroundStyle(ClosetTheme.textPrimary)
                                Spacer()
                                Button("重置布局") {
                                    draft.itemLayouts = defaultLayouts(for: Array(draft.itemIDs))
                                }
                                .font(.system(size: metrics.value(12), weight: .semibold))
                                .foregroundStyle(ClosetTheme.indigo)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                            OutfitCanvasBoard(
                                items: store.activeWardrobeItems.filter { draft.itemIDs.contains($0.id) },
                                layouts: $draft.itemLayouts,
                                metrics: metrics,
                                isEditable: true
                            )
                            .padding(.horizontal, 20)

                            Text("支持拖拽、双指缩放和旋转，调整每件衣服在底稿里的位置。")
                                .font(.system(size: metrics.value(12), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                        }
                    }

                    Divider()

                    // ― Title field ―――――――――――――――――――――――――
                    HStack {
                        Text("搞配名称")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ClosetTheme.textSecondary)
                        TextField("搞配名称", text: $draft.title)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    Divider()

                    // ― Item selection ――――――――――――――――――――――
                    VStack(alignment: .leading, spacing: metrics.value(16)) {
                        ForEach(WardrobeSection.allCases) { section in
                            let sectionItems = store.activeWardrobeItems.filter { $0.section == section }
                            if !sectionItems.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(ClosetTheme.textSecondary)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 14)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(sectionItems) { item in
                                                let selected = draft.itemIDs.contains(item.id)
                                                VStack(spacing: 6) {
                                                    MiniGarmentCard(
                                                        symbol: item.symbol,
                                                        gradientName: item.gradientName,
                                                        imageFileName: item.imageFileName,
                                                        metrics: metrics
                                                    )
                                                    .frame(width: 76, height: 96)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 18)
                                                            .stroke(selected ? ClosetTheme.indigo : Color.clear, lineWidth: 2.5)
                                                    )

                                                    Text(item.name)
                                                        .font(.system(size: 11, weight: selected ? .bold : .medium))
                                                        .foregroundStyle(selected ? ClosetTheme.indigo : ClosetTheme.textSecondary)
                                                        .lineLimit(1)
                                                        .frame(width: 76)
                                                }
                                                .onTapGesture {
                                                    if selected {
                                                        draft.itemIDs.remove(item.id)
                                                        draft.itemLayouts.removeAll { $0.itemID == item.id }
                                                    } else {
                                                        // Remove other items in same section
                                                        let removedIDs = draft.itemIDs.filter { existingID in
                                                            guard let existing = store.activeWardrobeItems.first(where: { $0.id == existingID }) else { return false }
                                                            return existing.section != section
                                                        }
                                                        draft.itemIDs = removedIDs
                                                        draft.itemLayouts.removeAll { layout in
                                                            !removedIDs.contains(layout.itemID)
                                                        }
                                                        draft.itemIDs.insert(item.id)
                                                        if !draft.itemLayouts.contains(where: { $0.itemID == item.id }) {
                                                            draft.itemLayouts.append(defaultLayout(for: item.id, section: section))
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 12)
                                    }

                                    Divider()
                                }
                            }
                        }
                    }

                    // ― Action buttons ――――――――――――――――――――――
                    HStack(spacing: 12) {
                        Button {
                            store.updateOutfit(look.id, from: draft, photoData: nil)
                            dismiss()
                        } label: {
                            Text("保存更改")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(ClosetTheme.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ClosetTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(ClosetTheme.secondaryCard)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    Button(role: .destructive) {
                        store.deleteOutfit(look.id)
                        dismiss()
                    } label: {
                        Text("删除这套搞配")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red.opacity(0.75))
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("编辑搞配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.6))
                    }
                }
            }
            .onAppear {
                draft = OutfitDraft(outfit: look)
                if draft.itemLayouts.isEmpty {
                    draft.itemLayouts = defaultLayouts(for: Array(draft.itemIDs))
                }
            }
        }
    }

    private func defaultLayout(for itemID: UUID, section: WardrobeSection) -> OutfitItemLayout {
        switch section {
        case .top:
            return OutfitItemLayout(itemID: itemID, x: 0.5, y: 0.2, scale: 1.02, rotation: 0)
        case .bottom:
            return OutfitItemLayout(itemID: itemID, x: 0.5, y: 0.53, scale: 0.98, rotation: 0)
        case .dress:
            return OutfitItemLayout(itemID: itemID, x: 0.5, y: 0.42, scale: 1.05, rotation: 0)
        case .shoes:
            return OutfitItemLayout(itemID: itemID, x: 0.5, y: 0.8, scale: 0.92, rotation: 0)
        case .uncategorized:
            return OutfitItemLayout(itemID: itemID, x: 0.76, y: 0.48, scale: 0.92, rotation: 0)
        }
    }

    private func defaultLayouts(for itemIDs: [UUID]) -> [OutfitItemLayout] {
        itemIDs.compactMap { itemID in
            guard let item = store.activeWardrobeItems.first(where: { $0.id == itemID }) else { return nil }
            return defaultLayout(for: itemID, section: item.section)
        }
    }
}

struct CalendarDayCell: View {
    let day: Int?
    let marker: DiaryMarker?
    let isSelected: Bool
    let metrics: LayoutMetrics

    var body: some View {
        VStack(spacing: metrics.value(4)) {
            if let day {
                Text("\(day)")
                    .font(.system(size: metrics.value(14), weight: isSelected ? .bold : .medium))
                    .foregroundStyle(ClosetTheme.textPrimary)
            } else {
                Text("")
                    .font(.system(size: metrics.value(14), weight: .medium))
                    .hidden()
            }

            if let marker {
                HStack(spacing: metrics.value(4)) {
                    if marker.hasPhoto {
                        Circle().fill(ClosetTheme.rose).frame(width: metrics.value(6), height: metrics.value(6))
                    }
                    if marker.hasOutfit {
                        Circle().fill(ClosetTheme.indigo).frame(width: metrics.value(6), height: metrics.value(6))
                    }
                }
                .frame(height: metrics.value(16))
            } else {
                Spacer()
                    .frame(height: metrics.value(16))
            }
        }
        .frame(height: metrics.value(52))
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.value(2))
        .background(isSelected ? ClosetTheme.indigo.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ClosetTheme.line.opacity(0.75))
                .frame(height: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ClosetTheme.line.opacity(0.75))
                .frame(width: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: metrics.value(14))
                .stroke(isSelected ? ClosetTheme.indigo.opacity(0.9) : .clear, lineWidth: 2)
                .padding(.horizontal, metrics.value(4))
                .padding(.vertical, metrics.value(3))
        }
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(6)) {
            Circle().fill(color).frame(width: metrics.value(10), height: metrics.value(10))
            Text(title)
                .font(.system(size: metrics.value(13), weight: .medium))
                .foregroundStyle(ClosetTheme.textSecondary)
        }
    }
}

struct TodayOutfitSection: View {
    @ObservedObject var store: ClosetStore
    let date: Date
    let metrics: LayoutMetrics
    let onEdit: () -> Void

    private var draft: DiaryDraft {
        store.draftForDiary(on: date)
    }

    private var photoImage: UIImage? {
        guard let fileName = draft.photoFileName else { return nil }
        return LocalImageStore.shared.loadImage(named: fileName)
    }

    private var linkedItems: [ClosetItem] {
        let resolvedItemIDs: [UUID]
        if !draft.itemIDs.isEmpty {
            resolvedItemIDs = draft.itemIDs
        } else if let outfitID = draft.outfitID,
                  let outfit = store.savedLooks.first(where: { $0.id == outfitID }) {
            resolvedItemIDs = outfit.itemIDs
        } else {
            resolvedItemIDs = []
        }

        return resolvedItemIDs.compactMap { id in
            store.wardrobeItems.first(where: { $0.id == id })
        }
    }

    var body: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: metrics.value(12)) {
                HStack {
                    Text("当日穿搭")
                        .font(.system(size: metrics.value(16), weight: .heavy))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    Spacer()
                    Button("编辑", action: onEdit)
                        .font(.system(size: metrics.value(12), weight: .bold))
                        .foregroundStyle(ClosetTheme.indigo)
                }

                HStack(alignment: .top, spacing: metrics.value(12)) {
                    VStack(alignment: .leading, spacing: metrics.value(8)) {
                        Text("当日实拍")
                            .font(.system(size: metrics.value(12), weight: .bold))
                            .foregroundStyle(ClosetTheme.textSecondary)

                        ZStack {
                            RoundedRectangle(cornerRadius: metrics.value(22), style: .continuous)
                                .fill(Color.white.opacity(0.68))

                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                VStack(spacing: metrics.value(8)) {
                                    Image(systemName: "camera.macro")
                                        .font(.system(size: metrics.value(28), weight: .light))
                                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.45))
                                    Text("今天还没有实拍")
                                        .font(.system(size: metrics.value(11), weight: .medium))
                                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.7))
                                }
                                .padding(metrics.value(12))
                            }
                        }
                        .frame(width: metrics.contentWidth * 0.36, height: metrics.value(180))
                        .clipShape(RoundedRectangle(cornerRadius: metrics.value(22), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.value(22), style: .continuous)
                                .stroke(.white.opacity(0.8), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: metrics.value(8)) {
                        Text("当日搭配")
                            .font(.system(size: metrics.value(12), weight: .bold))
                            .foregroundStyle(ClosetTheme.textSecondary)

                        RoundedRectangle(cornerRadius: metrics.value(22), style: .continuous)
                            .fill(Color.white.opacity(0.6))
                            .overlay {
                                if linkedItems.isEmpty {
                                    VStack(spacing: metrics.value(8)) {
                                        Image(systemName: "square.stack.3d.up.slash")
                                            .font(.system(size: metrics.value(26), weight: .light))
                                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.42))
                                        Text("今天还没有关联衣服")
                                            .font(.system(size: metrics.value(11), weight: .medium))
                                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.72))
                                    }
                                    .padding(metrics.value(12))
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: metrics.value(10)) {
                                            ForEach(linkedItems) { item in
                                                VStack(alignment: .leading, spacing: metrics.value(8)) {
                                                    MiniGarmentCard(
                                                        symbol: item.symbol,
                                                        gradientName: item.gradientName,
                                                        imageFileName: item.imageFileName,
                                                        metrics: metrics
                                                    )
                                                    .frame(width: metrics.value(94), height: metrics.value(126))

                                                    Text(item.name)
                                                        .font(.system(size: metrics.value(11), weight: .semibold))
                                                        .foregroundStyle(ClosetTheme.textPrimary)
                                                        .lineLimit(1)

                                                    Text(item.section.rawValue)
                                                        .font(.system(size: metrics.value(10), weight: .medium))
                                                        .foregroundStyle(ClosetTheme.textSecondary)
                                                }
                                                .frame(width: metrics.value(94), alignment: .leading)
                                            }
                                        }
                                        .padding(metrics.value(12))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.value(180))
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.value(22), style: .continuous)
                                    .stroke(.white.opacity(0.75), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}

struct AnalyticsTabLabel: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics
    var selected: Bool = false

    var body: some View {
        HStack(spacing: metrics.value(6)) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: metrics.value(16), weight: .bold))
        .foregroundStyle(selected ? .white : ClosetTheme.textSecondary)
        .padding(.horizontal, metrics.value(14))
        .frame(height: metrics.value(54))
        .background(selected ? AnyShapeStyle(ClosetTheme.accentGradient) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(20)))
    }
}

struct MetricCard: View {
    let stat: AnalysisStat
    let metrics: LayoutMetrics

    private var toneColor: Color {
        switch stat.tone {
        case "mint": ClosetTheme.mint
        case "sky": ClosetTheme.sky
        case "rose": ClosetTheme.rose
        default: ClosetTheme.yellow
        }
    }

    var body: some View {
        FrostedCard(padding: metrics.value(16)) {
            VStack(spacing: metrics.value(6)) {
                Text(stat.value)
                    .font(.system(size: metrics.value(21), weight: .heavy))
                    .foregroundStyle(toneColor)
                Text(stat.label)
                    .font(.system(size: metrics.value(14), weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct FormMetricRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(alignment: .bottom, spacing: metrics.value(10)) {
            Image(systemName: icon)
                .font(.system(size: metrics.value(20), weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: metrics.value(24))

            VStack(alignment: .leading, spacing: metrics.value(6)) {
                Text(title)
                    .font(.system(size: metrics.value(16), weight: .bold))
                    .foregroundStyle(ClosetTheme.textSecondary)

                HStack {
                    Text(value)
                        .font(.system(size: metrics.value(18), weight: .medium))
                        .foregroundStyle(ClosetTheme.textPrimary)
                        .padding(.horizontal, metrics.value(14))
                        .frame(height: metrics.value(52))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.value(14))
                                .stroke(ClosetTheme.line, lineWidth: 1.5)
                        )

                    Text(unit)
                        .font(.system(size: metrics.value(16), weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.75))
                        .padding(.leading, 2)
                }
            }
        }
    }
}

struct BodyPhotoCard: View {
    let photo: ProfilePhotoDisplay
    let metrics: LayoutMetrics

    var body: some View {
        VStack(spacing: metrics.value(8)) {
            NineSixteenMediaFrame(cornerRadius: metrics.value(16)) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.94, green: 0.94, blue: 0.92), .white], startPoint: .top, endPoint: .bottom)

                    if let remoteURL = photo.remoteURL {
                        AsyncImage(url: remoteURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                placeholderBodyPhoto
                            }
                        }
                    } else if let image = LocalImageStore.shared.loadImage(named: photo.localFileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholderBodyPhoto
                    }
                }
            }
            Text(photo.title)
                .font(.system(size: metrics.value(13.5), weight: .bold))
                .foregroundStyle(ClosetTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderBodyPhoto: some View {
        Image(systemName: photo.symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 0.58))
            .padding(metrics.value(22))
    }
}

struct GradientCapsuleButton: View {
    let title: String
    let icon: String
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: metrics.value(8)) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: metrics.value(16), weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.value(16))
        .frame(height: metrics.value(48))
        .background(ClosetTheme.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(16)))
    }
}

struct FrostedCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClosetTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: ClosetTheme.tabShadow, radius: 20, y: 12)
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: ClosetTab
    let metrics: LayoutMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClosetTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: metrics.value(5)) {
                        ZStack {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: metrics.value(12))
                                    .fill(ClosetTheme.accentGradient)
                                    .frame(width: metrics.value(46), height: metrics.value(34))
                                    .shadow(color: ClosetTheme.indigo.opacity(0.3), radius: 8, y: 4)
                            }
                            Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                                .font(.system(size: metrics.value(20), weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .white : ClosetTheme.textSecondary.opacity(0.55))
                        }
                        .frame(height: metrics.value(34))

                        Text(tab.title)
                            .font(.system(size: metrics.value(12), weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? ClosetTheme.indigo : ClosetTheme.textSecondary.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, metrics.value(12))
        .padding(.top, metrics.value(12))
        .padding(.bottom, metrics.value(16))
        .background(.white.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(28)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(28))
                .stroke(ClosetTheme.line.opacity(0.7), lineWidth: 1.5)
        )
        .shadow(color: ClosetTheme.tabShadow, radius: 28, y: 14)
    }
}

struct WardrobeItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: WardrobeViewModel
    let metrics: LayoutMetrics
    var editingItem: ClothingItem? = nil

    @State private var name = ""
    @State private var category: ClothingCategory = .top
    @State private var color = ""
    @State private var brand = ""
    @State private var price = ""
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var tagsText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var detectedImageBase64: String?
    @State private var isProcessingPhoto = false
    @State private var isAutoTagging = false
    @State private var photoProcessingStatus: LocalPhotoProcessingStatus?

    private var isEditing: Bool { editingItem != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        RemotePhotoPreviewCard(
                            imageData: selectedPhotoData,
                            imageURLString: editingItem?.imageFront,
                            placeholderSystemName: category.systemImageName
                        )
                    }

                    if isProcessingPhoto {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在本地抠图...")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let photoProcessingStatus {
                        LocalPhotoProcessingBanner(status: photoProcessingStatus)
                    }

                    if selectedPhotoData != nil {
                        Button("AI 自动识别") {
                            Task {
                                guard let detectedImageBase64 else { return }
                                isAutoTagging = true
                                defer { isAutoTagging = false }
                                if let response = await viewModel.autoTag(imageBase64: detectedImageBase64) {
                                    applyAutoTag(response)
                                }
                            }
                        }
                        .disabled(isAutoTagging)
                    }

                    if isAutoTagging {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在用 Qwen2.5-VL 识别服装信息...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("基础信息") {
                    TextField("名称", text: $name)
                    Picker("分类", selection: $category) {
                        ForEach(ClothingCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    TextField("颜色", text: $color)
                    TextField("品牌", text: $brand)
                    TextField("价格", text: $price)
                        .keyboardType(.decimalPad)
                    Toggle("记录购买日期", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                    }
                }

                Section("标签") {
                    TextField("用逗号分隔，例如：通勤, 春季, 基础款", text: $tagsText, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ClosetTheme.rose)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑单品" : "新增单品")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSaving ? "保存中..." : "保存") {
                        Task {
                            let success: Bool
                            if let editingItem {
                                success = await viewModel.updateItem(id: editingItem.id, request: requestBody)
                            } else {
                                success = await viewModel.createItem(requestBody)
                            }
                            if success {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isFormValid || viewModel.isSaving || isProcessingPhoto)
                }

                if let editingItem {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除单品", role: .destructive) {
                            Task {
                                if await viewModel.deleteItem(id: editingItem.id) {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .onAppear(perform: populateForm)
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                guard let rawData = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
                isProcessingPhoto = true
                defer { isProcessingPhoto = false }
                let result = await BackgroundRemovalService.shared.prepareWardrobeImage(from: rawData)
                selectedPhotoData = result.imageData
                detectedImageBase64 = result.imageData.base64EncodedString()
                photoProcessingStatus = LocalPhotoProcessingStatus(
                    message: result.localizedStatusMessage,
                    tone: result.didRemoveBackground ? .success : .info,
                    detail: result.didRemoveBackground
                        ? "图片已在本地优化，可继续自动识别或直接保存。"
                        : (result.localizedFailureDetail ?? "当前图片保留原图继续使用，不影响后续录入。")
                )
            }
        }
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var requestBody: WardrobeItemUpsertRequest {
        WardrobeItemUpsertRequest(
            imageFront: detectedImageBase64,
            category: category,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.nilIfBlank,
            price: Double(price),
            purchaseDate: hasPurchaseDate ? purchaseDate.apiDateString : nil,
            tags: tagsText.tagList
        )
    }

    private func populateForm() {
        guard let editingItem else { return }
        name = editingItem.name
        category = editingItem.category
        color = editingItem.color
        brand = editingItem.brand ?? ""
        price = editingItem.price.map { String(Int($0)) } ?? ""
        if let purchaseDate = editingItem.purchaseDate?.dateFromAPIString {
            self.purchaseDate = purchaseDate
            hasPurchaseDate = true
        }
        tagsText = editingItem.tags.joined(separator: ", ")
        selectedPhotoData = nil
        detectedImageBase64 = editingItem.imageFront
        photoProcessingStatus = nil
    }

    private func applyAutoTag(_ response: AutoTagResponse) {
        if let name = response.name, !name.isEmpty { self.name = name }
        if let category = response.category { self.category = category }
        if let color = response.color, !color.isEmpty { self.color = color }
        if let brand = response.brand, !brand.isEmpty { self.brand = brand }
        if let tags = response.tags, !tags.isEmpty { self.tagsText = tags.joined(separator: ", ") }
    }
}

struct RemotePhotoPreviewCard: View {
    enum LayoutStyle {
        case inline
        case hero
    }

    let imageData: Data?
    let imageURLString: String?
    let placeholderSystemName: String
    var layoutStyle: LayoutStyle = .inline

    var body: some View {
        Group {
            switch layoutStyle {
            case .inline:
                GarmentPreviewWindow {
                    imageContent(padding: 12, placeholderSize: 44)
                }
            case .hero:
                VStack(alignment: .leading, spacing: 14) {
                    GarmentPreviewWindow(cornerRadius: 22) {
                        imageContent(padding: 16, placeholderSize: 52)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)

                    Text("导入区按 9:16 比例预览，记录页和浏览页会保持同一张视觉比例。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func imageContent(padding: CGFloat, placeholderSize: CGFloat) -> some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(padding)
        } else if let imageURLString, let url = URL(string: imageURLString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(padding)
                } else {
                    garmentPlaceholder(size: placeholderSize)
                }
            }
        } else {
            garmentPlaceholder(size: placeholderSize)
        }
    }

    private func garmentPlaceholder(size: CGFloat) -> some View {
        Image(systemName: placeholderSystemName)
            .resizable()
            .scaledToFit()
            .padding(size)
            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.45))
    }
}

private struct LocalPhotoProcessingStatus {
    enum Tone {
        case success
        case info

        var tint: Color {
            switch self {
            case .success: ClosetTheme.mint
            case .info: ClosetTheme.indigo
            }
        }

        var iconName: String {
            switch self {
            case .success: "checkmark.seal.fill"
            case .info: "info.circle.fill"
            }
        }
    }

    let message: String
    let tone: Tone
    let detail: String
}

private struct LocalPhotoProcessingBanner: View {
    let status: LocalPhotoProcessingStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.tone.iconName)
                .foregroundStyle(status.tone.tint)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 4) {
                Text(status.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClosetTheme.textPrimary)
                Text(status.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Brand Database
private enum BrandDatabase {
    static let all: [String] = [
        // 运动 / Sport
        "Nike", "adidas", "PUMA", "New Balance", "ASICS", "Reebok", "Under Armour",
        "Salomon", "The North Face", "Columbia", "Patagonia", "Arc'teryx",
        "Lululemon", "Gymshark", "On Running", "HOKA", "Brooks", "Mizuno",
        // 牛仔 / Denim
        "Levi's", "Wrangler", "Lee", "Diesel",
        // 街头 / Streetwear
        "Supreme", "Off-White", "A Bathing Ape", "Stüssy", "Carhartt WIP",
        "Palace", "KITH", "Fear of God", "Essentials", "Anti Social Social Club",
        "Human Made", "Neighborhood",
        // 轻奢 / Contemporary
        "COS", "ZARA", "H&M", "Uniqlo", "Mango", "& Other Stories",
        "Arket", "Weekday", "ASOS", "Gap", "Banana Republic", "J.Crew",
        "Massimo Dutti",
        // 设计师 / Designer
        "Ralph Lauren", "Tommy Hilfiger", "Calvin Klein", "Lacoste",
        "Fred Perry", "Gant", "Hackett",
        // 奢侈 / Luxury
        "Louis Vuitton", "Gucci", "Prada", "Chanel", "Dior", "Hermès",
        "Burberry", "Balenciaga", "Givenchy", "Saint Laurent",
        "Bottega Veneta", "Valentino", "Fendi", "Celine", "Loewe",
        "Alexander McQueen", "Versace", "Miu Miu", "Acne Studios",
        "Maison Margiela", "Rick Owens", "Comme des Garçons",
        // 国潮 / Chinese Brands
        "李宁", "安踏", "特步", "361°", "匹克", "鸿星尔克",
        "江南布衣", "太平鸟", "美特斯邦威", "波司登", "海澜之家",
        "UR", "MO&Co.", "Evisu",
        // 鞋履 / Footwear
        "Converse", "Vans", "Dr. Martens", "Birkenstock", "UGG",
        "Timberland", "Clarks", "Tod's",
        // 其他 / Others
        "未填写"
    ].sorted()

    /// 中文拼音首字母 / 关键词映射，用于拼音模糊搜索
    static let aliases: [String: [String]] = [
        "adidas": ["阿迪达斯", "阿迪", "ad"],
        "Nike": ["耐克", "nk"],
        "PUMA": ["彪马"],
        "New Balance": ["新百伦", "nb"],
        "ASICS": ["亚瑟士"],
        "Reebok": ["锐步"],
        "Under Armour": ["安德玛", "ua"],
        "Lululemon": ["露露柠檬"],
        "The North Face": ["北面", "tnf"],
        "Columbia": ["哥伦比亚"],
        "Patagonia": ["巴塔哥尼亚"],
        "Arc'teryx": ["始祖鸟"],
        "Salomon": ["萨洛蒙"],
        "Levi's": ["李维斯", "levis"],
        "Supreme": ["supreme", "sp"],
        "Off-White": ["ow"],
        "A Bathing Ape": ["猿人头", "bape"],
        "COS": ["cos"],
        "ZARA": ["飒拉"],
        "Uniqlo": ["优衣库", "uniqlo"],
        "H&M": ["hm"],
        "Ralph Lauren": ["拉夫劳伦", "rl", "polo"],
        "Tommy Hilfiger": ["汤米", "tommy"],
        "Calvin Klein": ["ck"],
        "Lacoste": ["鳄鱼"],
        "Louis Vuitton": ["路易威登", "lv"],
        "Gucci": ["古驰"],
        "Prada": ["普拉达"],
        "Chanel": ["香奈儿"],
        "Dior": ["迪奥"],
        "Hermès": ["爱马仕", "hermes"],
        "Burberry": ["博柏利", "巴宝莉"],
        "Balenciaga": ["巴黎世家"],
        "Givenchy": ["纪梵希"],
        "Saint Laurent": ["圣罗兰", "ysl"],
        "Bottega Veneta": ["葆蝶家", "bv"],
        "Valentino": ["华伦天奴"],
        "Fendi": ["芬迪"],
        "Versace": ["范思哲"],
        "Converse": ["匡威"],
        "Vans": ["万斯"],
        "Dr. Martens": ["马丁", "马丁靴"],
        "Timberland": ["踢不烂"],
        "Clarks": ["其乐"],
        "Maison Margiela": ["mm6", "马吉拉"],
        "Comme des Garçons": ["cdg", "川久保玲"],
        "Acne Studios": ["acne"],
        "Rick Owens": ["rick"],
    ]

    static func matches(query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [String] = []
        for brand in all {
            let brandLower = brand.lowercased()
            if brandLower.contains(q) {
                results.append(brand)
                continue
            }
            if let aliasKeys = aliases[brand] {
                if aliasKeys.contains(where: { $0.lowercased().contains(q) }) {
                    results.append(brand)
                }
            }
        }
        return results
    }
}

// MARK: - BrandPickerField
private struct BrandPickerField: View {
    let label: String
    @Binding var text: String
    @State private var suggestions: [String] = []
    @State private var showDropdown = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(label, text: $text)
                    .focused($isFocused)
                    .onChange(of: text) { _, newVal in
                        suggestions = BrandDatabase.matches(query: newVal)
                        showDropdown = !suggestions.isEmpty
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showDropdown = false
                            }
                        } else {
                            suggestions = BrandDatabase.matches(query: text)
                            showDropdown = !suggestions.isEmpty
                        }
                    }
                if !text.isEmpty {
                    Button { text = ""; suggestions = []; showDropdown = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showDropdown {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { brand in
                            Button {
                                text = brand
                                showDropdown = false
                                isFocused = false
                            } label: {
                                HStack {
                                    Text(brand)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .opacity(text == brand ? 1 : 0)
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }
        }
    }
}

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClosetStore
    let metrics: LayoutMetrics
    var editingItem: ClosetItem? = nil
    var initialPhotoItems: [PhotosPickerItem] = []

    @State private var draft = AddItemDraft()
    @State private var importedDrafts: [ImportedItemDraft] = []
    @State private var selectedImportIndex = 0
    @State private var replacementPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isPreparingPhotos = false

    private var isEditing: Bool { editingItem != nil }
    private var isBatchImport: Bool { !isEditing && importedDrafts.count > 1 }
    private var currentImportedDraft: ImportedItemDraft? {
        guard importedDrafts.indices.contains(selectedImportIndex) else { return nil }
        return importedDrafts[selectedImportIndex]
    }
    private var currentPhotoData: Data? {
        isEditing ? selectedPhotoData : currentImportedDraft?.photoData
    }
    private var currentDraft: AddItemDraft {
        isEditing ? draft : (currentImportedDraft?.draft ?? AddItemDraft())
    }
    private var canSave: Bool {
        isEditing
            ? (selectedPhotoData != nil || draft.imageFileName != nil)
            : !importedDrafts.isEmpty && importedDrafts.allSatisfy { $0.photoData != nil }
    }
    private var saveButtonTitle: String {
        if isEditing { return "保存" }
        return isBatchImport ? "全部保存" : "保存"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片") {
                    if isEditing {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            PhotoPreviewCard(
                                title: "更换照片",
                                imageData: currentPhotoData,
                                storedFileName: draft.imageFileName,
                                placeholderSystemName: currentDraft.section.symbol,
                                layoutStyle: .hero
                            )
                        }
                    } else if isBatchImport {
                        VStack(spacing: metrics.value(10)) {
                            TabView(selection: $selectedImportIndex) {
                                ForEach(Array(importedDrafts.indices), id: \.self) { index in
                                    PhotosPicker(selection: $replacementPhotoItem, matching: .images) {
                                        PhotoPreviewCard(
                                            title: "",
                                            imageData: importedDrafts[index].photoData,
                                            storedFileName: nil,
                                            placeholderSystemName: importedDrafts[index].draft.section.symbol,
                                            layoutStyle: .hero
                                        )
                                    }
                                    .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: metrics.value(390))

                            Text("\(selectedImportIndex + 1) / \(importedDrafts.count)")
                                .font(.system(size: metrics.value(15), weight: .semibold))
                                .foregroundStyle(ClosetTheme.indigo)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        PhotosPicker(selection: $replacementPhotoItem, matching: .images) {
                            PhotoPreviewCard(
                                title: "更换照片",
                                imageData: currentPhotoData,
                                storedFileName: nil,
                                placeholderSystemName: currentDraft.section.symbol,
                                layoutStyle: .hero
                            )
                        }
                    }

                    if isPreparingPhotos {
                        HStack(spacing: metrics.value(10)) {
                            ProgressView()
                            Text("正在处理照片...")
                                .font(.system(size: metrics.value(13), weight: .medium))
                                .foregroundStyle(ClosetTheme.textSecondary)
                        }
                    }
                }

                Section("基础信息") {
                    TextField("名称（可不填）", text: draftBinding(\.name))
                    Picker("分类", selection: draftBinding(\.section)) {
                        ForEach(WardrobeSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    TextField("颜色（可不填）", text: draftBinding(\.color))
                    BrandPickerField(label: "品牌（可不填）", text: draftBinding(\.brand))
                    TextField("价格（可不填）", text: draftBinding(\.price))
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(isEditing ? "编辑单品" : "新增单品")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saveButtonTitle) {
                        if let itemID = editingItem?.id {
                            store.updateItem(itemID, from: normalizedDraftForSave(draft), photoData: selectedPhotoData)
                        } else {
                            for item in importedDrafts {
                                store.addItem(from: normalizedDraftForSave(item.draft), photoData: item.photoData)
                            }
                        }
                        dismiss()
                    }
                    .disabled(!canSave || isPreparingPhotos)
                }
                if isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除单品", role: .destructive) {
                            guard let itemID = editingItem?.id else { return }
                            store.deleteItem(itemID)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let editingItem {
                    draft = AddItemDraft(item: editingItem)
                    selectedPhotoData = nil
                }
            }
            .task {
                guard !isEditing, importedDrafts.isEmpty, !initialPhotoItems.isEmpty else { return }
                await prepareImportedPhotos(from: initialPhotoItems)
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                guard let rawData = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
                await replaceEditingPhoto(with: rawData)
            }
            .task(id: replacementPhotoItem) {
                guard let replacementPhotoItem else { return }
                guard let rawData = try? await replacementPhotoItem.loadTransferable(type: Data.self) else { return }
                await replaceImportedPhoto(with: rawData, at: selectedImportIndex)
            }
        }
    }

    private func draftBinding<T>(_ keyPath: WritableKeyPath<AddItemDraft, T>) -> Binding<T> {
        Binding(
            get: { currentDraft[keyPath: keyPath] },
            set: { newValue in
                updateCurrentDraft { nextDraft in
                    nextDraft[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func updateCurrentDraft(_ update: (inout AddItemDraft) -> Void) {
        if isEditing {
            update(&draft)
            return
        }
        guard importedDrafts.indices.contains(selectedImportIndex) else { return }
        update(&importedDrafts[selectedImportIndex].draft)
    }

    @MainActor
    private func prepareImportedPhotos(from items: [PhotosPickerItem]) async {
        isPreparingPhotos = true
        defer { isPreparingPhotos = false }

        var drafts: [ImportedItemDraft] = []
        for item in items {
            guard let rawData = try? await item.loadTransferable(type: Data.self) else { continue }
            if let prepared = await makeImportedDraft(from: rawData) {
                drafts.append(prepared)
            }
        }
        importedDrafts = drafts
        selectedImportIndex = 0
    }

    @MainActor
    private func replaceEditingPhoto(with rawData: Data) async {
        isPreparingPhotos = true
        defer { isPreparingPhotos = false }

        let result = await BackgroundRemovalService.shared.prepareWardrobeImage(from: rawData)
        selectedPhotoData = result.imageData
        let detection = await detectPhotoMetadata(for: result.imageData)
        draft.section = detection.section
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = detection.name
        }
        if draft.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.color = detection.color
        }
        if draft.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.brand = detection.brand
        }
        draft.gradientName = GarmentGradient(rawValue: detection.section.defaultGradientName) ?? draft.gradientName
    }

    @MainActor
    private func replaceImportedPhoto(with rawData: Data, at index: Int) async {
        guard importedDrafts.indices.contains(index) else { return }
        isPreparingPhotos = true
        defer { isPreparingPhotos = false }
        guard let prepared = await makeImportedDraft(from: rawData) else { return }
        importedDrafts[index] = prepared
    }

    @MainActor
    private func makeImportedDraft(from rawData: Data) async -> ImportedItemDraft? {
        let result = await BackgroundRemovalService.shared.prepareWardrobeImage(from: rawData)
        let detection = await detectPhotoMetadata(for: result.imageData)
        var draft = AddItemDraft()
        draft.name = detection.name
        draft.section = detection.section
        draft.color = detection.color
        draft.brand = detection.brand
        draft.gradientName = GarmentGradient(rawValue: detection.section.defaultGradientName) ?? .mist
        return ImportedItemDraft(photoData: result.imageData, draft: draft)
    }

    private func detectPhotoMetadata(for data: Data) async -> BatchPhotoDetectionResult {
        let image = UIImage(data: data)
        let recognition = await LocalClothingTypeRecognizer.shared.recognizeSection(from: image)
        let section = recognition.isConfident ? (recognition.section ?? .uncategorized) : .uncategorized
        let color = WardrobeSection.heuristicColorName(for: image)
        return BatchPhotoDetectionResult(
            section: section,
            name: WardrobeSection.localizedDefaultItemName(for: section, colorName: color),
            color: color,
            brand: "",
            categoryRecognitionLabel: recognitionLabel(for: recognition),
            categoryWasAutoDetected: section != .uncategorized
        )
    }

    private func recognitionLabel(for recognition: LocalClothingTypeRecognition) -> String {
        guard recognition.isConfident, let section = recognition.section else {
            return "未分类"
        }
        return "本地识别: \(section.rawValue)"
    }

    private func normalizedDraftForSave(_ input: AddItemDraft) -> AddItemDraft {
        var output = input
        output.gradientName = GarmentGradient(rawValue: output.section.defaultGradientName) ?? output.gradientName
        return output
    }

    private struct ImportedItemDraft: Identifiable {
        let id = UUID()
        var photoData: Data
        var draft: AddItemDraft
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
    }
}

private struct BatchPhotoDetectionResult {
    let section: WardrobeSection
    let name: String
    let color: String
    let brand: String
    let categoryRecognitionLabel: String
    let categoryWasAutoDetected: Bool
}

private struct DuplicateWarningCard: View {
    let candidates: [DuplicateCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可能已存在相似单品")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ClosetTheme.rose)
            ForEach(candidates) { candidate in
                Text("\(candidate.name) · \(candidate.section.rawValue) · 相似度 \(Int(candidate.score * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct BatchPhotoImportHero: View {
    let primaryTitle: String
    let subtitle: String
    let previewData: Data?
    let placeholderSystemName: String
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(14)) {
            GarmentPreviewWindow(cornerRadius: 22, thumbnailWidth: nil) {
                if let previewData, let image = UIImage(data: previewData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(metrics.value(16))
                } else {
                    VStack(spacing: metrics.value(10)) {
                        Image(systemName: placeholderSystemName)
                            .font(.system(size: metrics.value(42), weight: .medium))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.45))
                        Text("9:16 预览")
                            .font(.system(size: metrics.value(13), weight: .semibold))
                            .foregroundStyle(ClosetTheme.indigo)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.value(360))

            VStack(alignment: .leading, spacing: metrics.value(6)) {
                Label(primaryTitle, systemImage: "square.stack.3d.up")
                    .font(.system(size: metrics.value(16), weight: .bold))
                    .foregroundStyle(ClosetTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: metrics.value(13), weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DiaryLookSelectionCard: View {
    let title: String
    let look: OutfitPreview?
    let linkedItems: [ClosetItem]
    let isSelected: Bool
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.value(6)) {
            if let look {
                OutfitPreviewThumbnail(
                    look: look,
                    linkedItems: linkedItems,
                    metrics: metrics,
                    placeholderLabel: "暂无试穿图",
                    maxWidth: metrics.value(86)
                )
                .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: metrics.value(18))
                    .fill(ClosetTheme.secondaryCard)
                    .overlay {
                        Image(systemName: "nosign")
                            .font(.system(size: metrics.value(22), weight: .semibold))
                            .foregroundStyle(ClosetTheme.textSecondary.opacity(0.55))
                    }
                    .frame(width: metrics.value(86))
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
            }

            Text(title)
                .font(.system(size: metrics.value(11), weight: .semibold))
                .foregroundStyle(ClosetTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(metrics.value(6))
        .background(ClosetTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: metrics.value(20)))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.value(20))
                .stroke(isSelected ? ClosetTheme.indigo : .white.opacity(0.72), lineWidth: isSelected ? 2 : 1)
        )
        .frame(width: metrics.value(98))
    }
}

struct DiaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClosetStore
    let date: Date
    let metrics: LayoutMetrics

    @State private var draft = DiaryDraft()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var localDiaryMatchSummary: String?
    @State private var localDiaryMatchedItems: [LocalOutfitMatchResult.MatchedItem] = []
    @State private var localDiaryQualityWarning: String?
    @State private var pendingOutfitSuggestionID: UUID?
    @State private var pendingMatchedItems: [LocalOutfitMatchResult.MatchedItem] = []
    @State private var isShowingManualMatchEditor = false
    @State private var replacementSection: WardrobeSection?
    @State private var didEditAssociation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("备注") {
                    TextField("今天穿得怎么样？", text: $draft.note, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        PhotoPreviewCard(
                            title: "选择日记照片",
                            imageData: selectedPhotoData,
                            storedFileName: draft.photoFileName,
                            placeholderSystemName: "photo",
                            layoutStyle: .hero
                        )
                    }
                    if selectedPhotoData != nil || draft.photoFileName != nil {
                        Button("删除当前照片", role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                            store.removeDiaryPhoto(in: &draft)
                            draft.outfitID = nil
                            draft.itemIDs = []
                            draft.matchSource = .none
                            localDiaryMatchSummary = nil
                            localDiaryQualityWarning = nil
                            localDiaryMatchedItems = []
                            pendingMatchedItems = []
                            pendingOutfitSuggestionID = nil
                        }
                    }
                }

                Section("关联搭配") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: metrics.value(10)) {
                            DiaryLookSelectionCard(
                                title: "不关联",
                                look: nil,
                                linkedItems: [],
                                isSelected: draft.outfitID == nil,
                                metrics: metrics
                            )
                            .onTapGesture {
                                draft.outfitID = nil
                                draft.itemIDs = []
                                draft.matchSource = .none
                                localDiaryMatchedItems = []
                                localDiaryMatchSummary = nil
                                localDiaryQualityWarning = nil
                                pendingMatchedItems = []
                                pendingOutfitSuggestionID = nil
                                didEditAssociation = true
                            }

                            ForEach(store.activeSavedLooks) { look in
                                DiaryLookSelectionCard(
                                    title: look.title,
                                    look: look,
                                    linkedItems: look.itemIDs.compactMap { id in
                                        store.activeWardrobeItems.first(where: { $0.id == id })
                                    },
                                    isSelected: draft.outfitID == look.id,
                                    metrics: metrics
                                )
                                .onTapGesture {
                                    draft.outfitID = look.id
                                    draft.itemIDs = look.itemIDs
                                    draft.matchSource = .manuallyAdjusted
                                    localDiaryMatchedItems = look.itemIDs.compactMap { itemID in
                                        guard let item = store.activeWardrobeItems.first(where: { $0.id == itemID }) else { return nil }
                                        return LocalOutfitMatchResult.MatchedItem(
                                            id: item.id,
                                            section: item.section,
                                            confidence: 1
                                        )
                                    }
                                    localDiaryMatchSummary = "已关联到 \(look.title)"
                                    localDiaryQualityWarning = nil
                                    pendingMatchedItems = []
                                    pendingOutfitSuggestionID = nil
                                    didEditAssociation = true
                                }
                            }
                        }
                    }

                    if !pendingMatchedItems.isEmpty || pendingOutfitSuggestionID != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("本地匹配建议")
                                .font(.system(size: 13, weight: .semibold))
                            if let suggestedLook = store.activeSavedLooks.first(where: { $0.id == pendingOutfitSuggestionID }) {
                                Text("建议穿搭：\(suggestedLook.title)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ClosetTheme.indigo)
                            }
                            ForEach(pendingMatchedItems) { matched in
                                if let item = store.activeWardrobeItems.first(where: { $0.id == matched.id }) {
                                    diaryMatchRow(item: item, matched: matched, isPending: true, onRemove: {
                                        pendingMatchedItems.removeAll { $0.id == matched.id }
                                        pendingOutfitSuggestionID = recomputeSuggestedOutfitID(from: pendingMatchedItems.map(\.id))
                                    }, onReplace: {
                                        replacementSection = matched.section
                                        isShowingManualMatchEditor = true
                                    })
                                }
                            }
                            HStack {
                                Button("应用建议") {
                                    applyPendingMatchSuggestions()
                                }
                                .disabled(pendingMatchedItems.isEmpty && pendingOutfitSuggestionID == nil)

                                Button("手动修正") {
                                    isShowingManualMatchEditor = true
                                }

                                Button("忽略建议", role: .destructive) {
                                    clearPendingSuggestions(summary: "已忽略本地匹配建议")
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                    }

                    if let localDiaryMatchSummary {
                        Text(localDiaryMatchSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(localDiaryMatchSummary.contains("请手动选择") ? ClosetTheme.rose : ClosetTheme.textSecondary)
                    }

                    if let localDiaryQualityWarning {
                        Text(localDiaryQualityWarning)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ClosetTheme.rose)
                    }

                    if !localDiaryMatchedItems.isEmpty {
                        ForEach(localDiaryMatchedItems) { matched in
                            if let item = store.activeWardrobeItems.first(where: { $0.id == matched.id }) {
                                diaryMatchRow(item: item, matched: matched, isPending: false, onRemove: {
                                    localDiaryMatchedItems.removeAll { $0.id == matched.id }
                                    draft.itemIDs = localDiaryMatchedItems.map(\.id)
                                    draft.outfitID = recomputeSuggestedOutfitID(from: draft.itemIDs)
                                    draft.matchSource = draft.itemIDs.isEmpty ? .none : .manuallyAdjusted
                                    didEditAssociation = true
                                }, onReplace: {
                                    replacementSection = matched.section
                                    isShowingManualMatchEditor = true
                                })
                            }
                        }

                        Button("手动修正已应用结果") {
                            isShowingManualMatchEditor = true
                        }
                        .font(.system(size: 12, weight: .medium))

                        Button("清空已应用匹配结果", role: .destructive) {
                            draft.outfitID = nil
                            draft.itemIDs = []
                            draft.matchSource = .none
                            localDiaryMatchedItems = []
                            localDiaryMatchSummary = "已清空自动匹配结果"
                            localDiaryQualityWarning = nil
                            didEditAssociation = true
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .navigationTitle("编辑记录")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var draftToSave = draft
                        if !didEditAssociation, let existingEntry = store.diaryEntry(for: date) {
                            draftToSave.outfitID = existingEntry.outfitID
                            draftToSave.itemIDs = existingEntry.itemIDs
                            draftToSave.matchSource = existingEntry.matchSource
                        }
                        store.upsertDiaryEntry(for: date, draft: draftToSave, photoData: selectedPhotoData)
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = store.draftForDiary(on: date)
                selectedPhotoData = nil
                localDiaryMatchSummary = nil
                localDiaryQualityWarning = nil
                localDiaryMatchedItems = draft.itemIDs.compactMap { itemID in
                    guard let item = store.activeWardrobeItems.first(where: { $0.id == itemID }) else { return nil }
                    return LocalOutfitMatchResult.MatchedItem(
                        id: item.id,
                        section: item.section,
                        confidence: 1
                    )
                }
                pendingMatchedItems = []
                pendingOutfitSuggestionID = nil
                didEditAssociation = false
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                selectedPhotoData = try? await selectedPhotoItem.loadTransferable(type: Data.self)
                if selectedPhotoData != nil {
                    draft.hasPhoto = true
                }
                if let selectedPhotoData {
                    let match = await LocalOutfitMatcher.shared.matchDiaryPhoto(
                        selectedPhotoData,
                        wardrobeItems: store.activeWardrobeItems,
                        savedLooks: store.activeSavedLooks
                    )
                    pendingMatchedItems = match.matchedItems
                    pendingOutfitSuggestionID = match.outfitID
                    localDiaryMatchSummary = match.summary
                    localDiaryQualityWarning = match.qualityWarning
                    if match.matchedItems.isEmpty && match.outfitID == nil {
                        draft.matchSource = .none
                    } else {
                        draft.matchSource = .autoSuggested
                    }
                }
            }
            .sheet(isPresented: $isShowingManualMatchEditor) {
                NavigationStack {
                    List {
                        ForEach(store.activeWardrobeItems) { item in
                            if replacementSection == nil || item.section == replacementSection {
                            Button {
                                toggleManualMatchedItem(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.section.symbol)
                                        .foregroundStyle(ClosetTheme.indigo)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundStyle(ClosetTheme.textPrimary)
                                        Text(item.section.rawValue)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(ClosetTheme.textSecondary)
                                    }
                                    Spacer()
                                    if effectiveMatchedItemIDs.contains(item.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ClosetTheme.mint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            }
                        }
                    }
                    .navigationTitle("手动修正衣物")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") {
                                replacementSection = nil
                                isShowingManualMatchEditor = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("应用") {
                                applyManualSelection()
                                replacementSection = nil
                                isShowingManualMatchEditor = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var effectiveMatchedItemIDs: Set<UUID> {
        let pendingIDs = pendingMatchedItems.map(\.id)
        return Set((pendingIDs.isEmpty ? localDiaryMatchedItems.map(\.id) : pendingIDs))
    }

    @ViewBuilder
    private func diaryMatchRow(
        item: ClosetItem,
        matched: LocalOutfitMatchResult.MatchedItem,
        isPending: Bool,
        onRemove: @escaping () -> Void,
        onReplace: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.section.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPending ? ClosetTheme.indigo : ClosetTheme.mint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(matched.section.rawValue) · 匹配度 \(Int(matched.confidence * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary)
            }

            Spacer()

            Button("替换") {
                onReplace()
            }
            .font(.system(size: 11, weight: .semibold))

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
        }
        .padding(.vertical, 2)
    }

    private func applyPendingMatchSuggestions() {
        draft.itemIDs = pendingMatchedItems.map(\.id)
        draft.outfitID = pendingOutfitSuggestionID
        draft.matchSource = .autoApplied
        localDiaryMatchedItems = pendingMatchedItems
        localDiaryMatchSummary = pendingOutfitSuggestionID == nil ? "已应用本地衣物匹配建议" : "已应用本地穿搭匹配建议"
        pendingMatchedItems = []
        pendingOutfitSuggestionID = nil
        didEditAssociation = true
    }

    private func clearPendingSuggestions(summary: String) {
        pendingMatchedItems = []
        pendingOutfitSuggestionID = nil
        localDiaryMatchSummary = summary
        draft.matchSource = .none
        localDiaryQualityWarning = nil
        didEditAssociation = true
    }

    private func toggleManualMatchedItem(_ item: ClosetItem) {
        if let replacementSection {
            pendingMatchedItems.removeAll { $0.section == replacementSection }
        }
        if let index = pendingMatchedItems.firstIndex(where: { $0.id == item.id }) {
            pendingMatchedItems.remove(at: index)
        } else if let index = localDiaryMatchedItems.firstIndex(where: { $0.id == item.id }), pendingMatchedItems.isEmpty {
            pendingMatchedItems = localDiaryMatchedItems
            pendingMatchedItems.remove(at: index)
        } else {
            if pendingMatchedItems.isEmpty {
                pendingMatchedItems = localDiaryMatchedItems
            }
            pendingMatchedItems.append(
                LocalOutfitMatchResult.MatchedItem(
                    id: item.id,
                    section: item.section,
                    confidence: 1
                )
            )
        }
    }

    private func applyManualSelection() {
        let selectedIDs = pendingMatchedItems.map(\.id)
        draft.itemIDs = selectedIDs
        draft.outfitID = recomputeSuggestedOutfitID(from: selectedIDs)
        draft.matchSource = selectedIDs.isEmpty ? .none : .manuallyAdjusted
        localDiaryMatchedItems = pendingMatchedItems
        localDiaryMatchSummary = selectedIDs.isEmpty ? "已清空匹配衣物" : "已手动修正匹配衣物"
        pendingMatchedItems = []
        pendingOutfitSuggestionID = nil
        localDiaryQualityWarning = nil
        didEditAssociation = true
    }

    private func recomputeSuggestedOutfitID(from itemIDs: [UUID]) -> UUID? {
        let matchedOutfit = store.activeSavedLooks
            .map { look in
                (id: look.id, overlap: look.itemIDs.filter { itemIDs.contains($0) }.count)
            }
            .filter { $0.overlap > 0 }
            .max { $0.overlap < $1.overlap }
        return (matchedOutfit?.overlap ?? 0) >= 2 ? matchedOutfit?.id : nil
    }
}

struct RemoteDiaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DiaryViewModel
    let date: Date
    let defaultWeather: String

    @State private var notes = ""
    @State private var weather = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var existingEntry: RemoteDiaryEntry?
    @State private var removeCurrentPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section("天气与备注") {
                    TextField("天气", text: $weather)
                    TextField("今天穿得怎么样？", text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                Section("照片") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        RemotePhotoPreviewCard(
                            imageData: selectedPhotoData,
                            imageURLString: removeCurrentPhoto ? nil : existingEntry?.photo,
                            placeholderSystemName: "photo",
                            layoutStyle: .hero
                        )
                    }

                    if selectedPhotoData != nil || existingEntry?.photo != nil {
                        Button("删除当前照片", role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                            removeCurrentPhoto = true
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ClosetTheme.rose)
                    }
                }
            }
            .navigationTitle("编辑记录")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSaving ? "保存中..." : "保存") {
                        Task {
                            let photoPayload: String?
                            if removeCurrentPhoto {
                                photoPayload = nil
                            } else if let selectedPhotoData {
                                photoPayload = selectedPhotoData.base64EncodedString()
                            } else {
                                photoPayload = existingEntry?.photo
                            }

                            let request = DiaryEntryUpsertRequest(
                                date: date.apiDateString,
                                weather: weather.nilIfBlank ?? defaultWeather,
                                mood: "普通",
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                clothingIds: [],
                                photo: photoPayload,
                                outfitId: existingEntry?.outfitId
                            )

                            if await viewModel.saveEntry(existingID: existingEntry?.id, request: request) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }

                if let existingEntry {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除记录", role: .destructive) {
                            Task {
                                if await viewModel.deleteEntry(id: existingEntry.id) {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .onAppear(perform: populateForm)
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                guard let rawData = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
                selectedPhotoData = rawData.optimizedWardrobeUploadData()
                removeCurrentPhoto = false
            }
        }
    }

    private func populateForm() {
        existingEntry = viewModel.entry(for: date)
        notes = existingEntry?.notes ?? ""
        weather = existingEntry?.weather ?? defaultWeather
        selectedPhotoData = nil
        removeCurrentPhoto = false
    }
}

struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClosetStore
    let metrics: LayoutMetrics

    @State private var draft = ProfileDraft()
    @State private var pendingBodyPhotoData: [UUID: Data] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section("个人信息") {
                    TextField("昵称", text: $draft.name)
                    TextField("身高 cm", text: $draft.heightCm)
                        .keyboardType(.numberPad)
                    TextField("体重 kg", text: $draft.weightKg)
                        .keyboardType(.numberPad)
                }

                Section("身形照片") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: metrics.value(10)), count: 3),
                        spacing: metrics.value(12)
                    ) {
                        ForEach(draft.bodyPhotos) { photo in
                            BodyPhotoPickerRow(
                                photo: photo,
                                previewData: pendingBodyPhotoData[photo.id],
                                onPhotoPicked: { data in
                                    pendingBodyPhotoData[photo.id] = data
                                },
                                onRemovePhoto: {
                                    pendingBodyPhotoData[photo.id] = nil
                                    store.removeBodyPhoto(photo.id, in: &draft)
                                },
                                compact: true,
                                metrics: metrics
                            )
                        }
                    }
                }
            }
            .navigationTitle("编辑资料")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var nextDraft = draft
                        for (photoID, data) in pendingBodyPhotoData {
                            store.updateBodyPhoto(photoID, imageData: data, in: &nextDraft)
                        }
                        store.updateProfile(from: nextDraft)
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = store.draftForProfile()
                pendingBodyPhotoData = [:]
            }
        }
    }
}

struct RemoteProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel

    @State private var name = ""
    @State private var heightCm = ""
    @State private var weightKg = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基础资料") {
                    TextField("昵称", text: $name)
                    TextField("身高 cm", text: $heightCm)
                        .keyboardType(.decimalPad)
                    TextField("体重 kg", text: $weightKg)
                        .keyboardType(.decimalPad)
                    TextField("风格偏好 / 备注", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("云端照片") {
                    Text("当前版本已接入云端照片展示；照片上传将在后续对齐后端上传协议后补齐。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ClosetTheme.rose)
                    }
                }
            }
            .navigationTitle("编辑资料")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSaving ? "保存中..." : "保存") {
                        Task {
                            guard let currentProfile = viewModel.profile else { return }
                            let nextProfile = BodyProfile(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                heightCm: Double(heightCm) ?? currentProfile.heightCm,
                                weightKg: Double(weightKg) ?? currentProfile.weightKg,
                                photoFront: currentProfile.photoFront,
                                photoSide: currentProfile.photoSide,
                                photoBack: currentProfile.photoBack,
                                description: description.nilIfBlank
                            )
                            if await viewModel.updateProfile(nextProfile) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.profile == nil || viewModel.isSaving)
                }
            }
            .task {
                if viewModel.profile == nil {
                    await viewModel.loadProfile()
                }
                populateForm()
            }
        }
    }

    private func populateForm() {
        guard let profile = viewModel.profile else { return }
        name = profile.name
        heightCm = profile.heightCm.formatted(.number.precision(.fractionLength(0 ... 1)))
        weightKg = profile.weightKg.formatted(.number.precision(.fractionLength(0 ... 1)))
        description = profile.description ?? ""
    }
}

private extension WardrobeFilter {
    func matches(_ category: ClothingCategory) -> Bool {
        switch self {
        case .all: true
        case .uncategorized: false
        case .top: category == .top
        case .bottom: category == .bottom
        case .dress: category == .dress
        case .outerwear: category == .outerwear
        case .shoes: category == .shoes
        case .accessory: category == .accessory
        }
    }
}

private extension ClothingCategory {
    var systemImageName: String {
        switch self {
        case .top: "tshirt"
        case .bottom: "figure.walk"
        case .dress: "sparkles"
        case .outerwear: "hanger"
        case .shoes: "shoeprints.fill"
        case .accessory: "handbag"
        }
    }
}

private extension WardrobeSection {
    init(category: ClothingCategory) {
        switch category {
        case .top, .outerwear, .accessory:
            self = .top
        case .bottom:
            self = .bottom
        case .dress:
            self = .dress
        case .shoes:
            self = .shoes
        }
    }

    static func heuristicCategory(for image: UIImage?) -> WardrobeSection {
        guard let image else { return .uncategorized }

        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let ratio = width / height

        if ratio > 1.15 {
            return .shoes
        }
        if height / width > 1.45 {
            return .dress
        }
        if height / width > 1.18 {
            return .bottom
        }
        return .uncategorized
    }

    static func heuristicColorName(for image: UIImage?) -> String {
        guard let image else { return "基础色" }
        let sample = image.averageColorComponents
        let brightness = (sample.red + sample.green + sample.blue) / 3
        let saturation = max(sample.red, max(sample.green, sample.blue)) - min(sample.red, min(sample.green, sample.blue))

        if brightness < 0.2 { return "黑色" }
        if brightness > 0.88 && saturation < 0.12 { return "白色" }
        if saturation < 0.1 { return brightness > 0.55 ? "灰色" : "深灰色" }
        if sample.red > sample.green * 1.18 && sample.red > sample.blue * 1.18 {
            return sample.green > 0.55 ? "米色" : "红色"
        }
        if sample.blue > sample.red * 1.12 && sample.blue > sample.green * 1.08 {
            return "蓝色"
        }
        if sample.green > sample.red * 1.08 && sample.green > sample.blue * 1.08 {
            return "绿色"
        }
        return brightness > 0.7 ? "浅色" : "深色"
    }

    static func localizedDefaultItemName(for section: WardrobeSection, colorName: String) -> String {
        switch section {
        case .uncategorized: "\(colorName)单品"
        case .top: "\(colorName)上装"
        case .bottom: "\(colorName)下装"
        case .dress: "\(colorName)连衣裙"
        case .shoes: "\(colorName)鞋履"
        }
    }

    var defaultGradientName: String {
        switch self {
        case .uncategorized: GarmentGradient.cloud.rawValue
        case .top: GarmentGradient.mist.rawValue
        case .bottom: GarmentGradient.denim.rawValue
        case .dress: GarmentGradient.sage.rawValue
        case .shoes: GarmentGradient.cloud.rawValue
        }
    }
}

extension UIImage {
    var averageColorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let inputImage = CIImage(image: self) else { return (0.8, 0.8, 0.8) }
        let extent = inputImage.extent
        let params: [String: Any] = [kCIInputImageKey: inputImage, kCIInputExtentKey: CIVector(cgRect: extent)]
        guard
            let filter = CIFilter(name: "CIAreaAverage", parameters: params),
            let outputImage = filter.outputImage
        else {
            return (0.8, 0.8, 0.8)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return (
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255
        )
    }

    var colorHistogram: [CGFloat] {
        guard let cgImage else { return Array(repeating: 0, count: 12) }
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Array(repeating: 0, count: 12)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var histogram = Array(repeating: CGFloat(0), count: 12)
        let bucketDivisor: CGFloat = 64

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = Int(floor(CGFloat(pixels[index]) / bucketDivisor))
            let g = Int(floor(CGFloat(pixels[index + 1]) / bucketDivisor))
            let b = Int(floor(CGFloat(pixels[index + 2]) / bucketDivisor))
            histogram[min(r, 3)] += 1
            histogram[4 + min(g, 3)] += 1
            histogram[8 + min(b, 3)] += 1
        }

        let total = max(CGFloat(width * height), 1)
        return histogram.map { $0 / total }
    }

    var edgeDensity: CGFloat {
        guard let cgImage else { return 0 }
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var edgeCount: CGFloat = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = pixelLuminance(x: x, y: y, width: width, data: pixels)
                let right = pixelLuminance(x: x + 1, y: y, width: width, data: pixels)
                let down = pixelLuminance(x: x, y: y + 1, width: width, data: pixels)
                let gradient = abs(center - right) + abs(center - down)
                if gradient > 0.14 {
                    edgeCount += 1
                }
            }
        }

        return edgeCount / CGFloat(width * height)
    }

    private func pixelLuminance(x: Int, y: Int, width: Int, data: [UInt8]) -> CGFloat {
        let offset = (y * width + x) * 4
        let r = CGFloat(data[offset]) / 255
        let g = CGFloat(data[offset + 1]) / 255
        let b = CGFloat(data[offset + 2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

private extension ClothingItem {
    var brandText: String {
        brand?.nilIfBlank ?? "未填写品牌"
    }

    var priceText: String {
        guard let price else { return "未标价" }
        if price.rounded() == price {
            return "¥\(Int(price))"
        }
        return "¥\(price.formatted(.number.precision(.fractionLength(0 ... 2))))"
    }

    var imageURL: URL? {
        guard let imageFront, let url = URL(string: imageFront) else { return nil }
        return url
    }

    var gradient: LinearGradient {
        switch category {
        case .top:
            LinearGradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.99), .white], startPoint: .top, endPoint: .bottom)
        case .bottom:
            LinearGradient(colors: [Color(red: 0.9, green: 0.95, blue: 1), .white], startPoint: .top, endPoint: .bottom)
        case .dress:
            LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.95), .white], startPoint: .top, endPoint: .bottom)
        case .outerwear:
            LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 0.98), .white], startPoint: .top, endPoint: .bottom)
        case .shoes:
            LinearGradient(colors: [Color(red: 0.91, green: 0.97, blue: 0.92), .white], startPoint: .top, endPoint: .bottom)
        case .accessory:
            LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.9), .white], startPoint: .top, endPoint: .bottom)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var tagList: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var dateFromAPIString: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: self)
    }
}

private extension Date {
    var apiDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

struct ProfilePhotoDisplay: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var localFileName: String? = nil
    var remoteURLString: String? = nil

    var remoteURL: URL? {
        guard let remoteURLString, let url = URL(string: remoteURLString) else { return nil }
        return url
    }
}

struct PhotoPreviewCard: View {
    enum LayoutStyle {
        case inline
        case hero
    }

    let title: String
    let imageData: Data?
    let storedFileName: String?
    let placeholderSystemName: String
    var layoutStyle: LayoutStyle = .inline

    var body: some View {
        Group {
            switch layoutStyle {
            case .inline:
                HStack(spacing: 14) {
                    previewWindow(cornerRadius: 16, thumbnailWidth: 92, innerPadding: 8, placeholderSize: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline)
                        Text("从相册导入，图片将保存到本地。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            case .hero:
                VStack(alignment: .leading, spacing: 14) {
                    previewWindow(cornerRadius: 22, thumbnailWidth: nil, innerPadding: 16, placeholderSize: 42)
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)

                    if !title.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(ClosetTheme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private func previewWindow(
        cornerRadius: CGFloat,
        thumbnailWidth: CGFloat?,
        innerPadding: CGFloat,
        placeholderSize: CGFloat
    ) -> some View {
        GarmentPreviewWindow(cornerRadius: cornerRadius, thumbnailWidth: thumbnailWidth) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(innerPadding)
            } else if let image = LocalImageStore.shared.loadImage(named: storedFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(innerPadding)
            } else {
                Image(systemName: placeholderSystemName)
                    .font(.system(size: placeholderSize, weight: .medium))
                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.55))
            }
        }
    }
}

private struct GarmentPreviewWindow<Content: View>: View {
    let cornerRadius: CGFloat
    let thumbnailWidth: CGFloat?
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 18, thumbnailWidth: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.thumbnailWidth = thumbnailWidth
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color(.secondarySystemBackground),
                        ClosetTheme.secondaryCard
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: max(cornerRadius - 3, 0))
                        .stroke(ClosetTheme.line.opacity(0.55), lineWidth: 1)
                    content
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .frame(maxWidth: thumbnailWidth ?? .infinity)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }
}

private struct NineSixteenMediaFrame<Content: View>: View {
    let maxWidth: CGFloat?
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat? = nil, cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
        }
        .frame(maxWidth: maxWidth ?? .infinity)
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        )
    }
}

struct BodyPhotoPickerRow: View {
    let photo: BodyPhoto
    let previewData: Data?
    let onPhotoPicked: (Data) -> Void
    let onRemovePhoto: () -> Void
    var compact: Bool = false
    let metrics: LayoutMetrics

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                if compact {
                    VStack(alignment: .leading, spacing: metrics.value(8)) {
                        GarmentPreviewWindow(cornerRadius: metrics.value(18), thumbnailWidth: nil) {
                            if let previewData, let image = UIImage(data: previewData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(metrics.value(10))
                            } else if let image = LocalImageStore.shared.loadImage(named: photo.imageFileName) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(metrics.value(10))
                            } else {
                                Image(systemName: photo.symbol)
                                    .font(.system(size: metrics.value(28), weight: .medium))
                                    .foregroundStyle(ClosetTheme.textSecondary.opacity(0.5))
                            }
                        }
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)

                        Text(photo.title)
                            .font(.system(size: metrics.value(12), weight: .semibold))
                            .foregroundStyle(ClosetTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    PhotoPreviewCard(
                        title: photo.title,
                        imageData: previewData,
                        storedFileName: photo.imageFileName,
                        placeholderSystemName: photo.symbol,
                        layoutStyle: .hero
                    )
                }
            }
            if previewData != nil || photo.imageFileName != nil {
                Button("删除当前照片", role: .destructive) {
                    onRemovePhoto()
                }
                .font(.system(size: compact ? metrics.value(11) : 15, weight: .medium))
                .frame(maxWidth: compact ? .infinity : nil, alignment: compact ? .center : .leading)
            }
        }
        .task(id: selectedItem) {
            guard let selectedItem else { return }
            if let data = try? await selectedItem.loadTransferable(type: Data.self) {
                onPhotoPicked(data)
            }
            self.selectedItem = nil
        }
    }
}
