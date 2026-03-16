//
//  closetTests.swift
//  closetTests
//
//  Created by 赵建华 on 2026/3/10.
//

import Foundation
import Testing
@testable import closet

struct closetTests {

    @MainActor
    @Test func archiveFilteringMovesItemsBetweenLists() async throws {
        let store = ClosetStore()
        let item = try #require(store.wardrobeItems.first)

        store.setArchived(item.id, isArchived: true)

        #expect(store.archivedWardrobeItems.contains(where: { $0.id == item.id }))
        #expect(!store.activeWardrobeItems.contains(where: { $0.id == item.id }))
    }

    @MainActor
    @Test func quickWearLoggingIncrementsWearCountImmediately() async throws {
        let store = ClosetStore()
        let item = try #require(store.wardrobeItems.first)
        let baseline = item.wearCount

        store.incrementWearCount(for: item.id)

        let updated = try #require(store.wardrobeItems.first(where: { $0.id == item.id }))
        #expect(updated.wearCount == baseline + 1)
    }

    @MainActor
    @Test func diaryRecomputeOverridesManualWearCountWithRecordedEntries() async throws {
        let store = ClosetStore()
        let items = Array(store.activeWardrobeItems.prefix(2))
        let first = try #require(items.first)
        let second = try #require(items.dropFirst().first)
        let itemIDs = [first.id, second.id]

        for item in [first, second] {
            store.incrementWearCount(for: item.id, amount: 3)
        }

        var draft = DiaryDraft()
        draft.itemIDs = itemIDs
        draft.matchSource = .manuallyAdjusted
        store.upsertDiaryEntry(for: Date(), draft: draft)

        let updatedItems = store.wardrobeItems.filter { itemIDs.contains($0.id) }
        #expect(updatedItems.allSatisfy { $0.wearCount == 1 })
    }

    @MainActor
    @Test func quickWearLoggingCreatesOrUpdatesTodayDiaryEntry() async throws {
        let store = ClosetStore()
        let item = try #require(store.activeWardrobeItems.first)

        store.logItemAsWornToday(item.id)

        let todayEntry = try #require(store.diaryEntry(for: Date()))
        #expect(todayEntry.itemIDs.contains(item.id))
        #expect(todayEntry.matchSource == .manuallyAdjusted)

        store.logItemAsWornToday(item.id)

        let updatedEntry = try #require(store.diaryEntry(for: Date()))
        #expect(updatedEntry.itemIDs.filter { $0 == item.id }.count == 1)
    }

    @MainActor
    @Test func archivedItemsAreExcludedFromActiveSavedLooks() async throws {
        let store = ClosetStore()
        let item = try #require(store.activeWardrobeItems.first)
        let saved = try #require(store.saveManualOutfit(itemIDs: [item.id]))

        #expect(store.activeSavedLooks.contains(where: { $0.id == saved.id }))

        store.setArchived(item.id, isArchived: true)

        #expect(!store.activeSavedLooks.contains(where: { $0.id == saved.id }))
    }

    @MainActor
    @Test func quickWearLoggingSupportsCustomDate() async throws {
        let store = ClosetStore()
        let item = try #require(store.activeWardrobeItems.first)
        let targetDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        store.logItemAsWorn(item.id, on: targetDate)

        let entry = try #require(store.diaryEntry(for: targetDate))
        #expect(entry.itemIDs.contains(item.id))
    }

    @MainActor
    @Test func batchArchiveAndDeleteOperateOnMultipleItems() async throws {
        let store = ClosetStore()
        let selectedIDs = Set(store.activeWardrobeItems.prefix(2).map(\.id))
        let baselineCount = store.wardrobeItems.count

        store.setArchived(selectedIDs, isArchived: true)
        #expect(store.archivedWardrobeItems.filter { selectedIDs.contains($0.id) }.count == selectedIDs.count)

        store.deleteItems(selectedIDs)
        #expect(store.wardrobeItems.count == baselineCount - selectedIDs.count)
    }

    @MainActor
    @Test func backupDocumentContainsSnapshotData() async throws {
        let store = ClosetStore()

        let backup = store.makeBackupDocument()

        #expect(backup.payload.snapshot.wardrobeItems.count == store.wardrobeItems.count)
        #expect(backup.payload.snapshot.savedLooks.count == store.savedLooks.count)
        #expect(backup.payload.snapshot.profile.name == store.profile.name)
    }

    @MainActor
    @Test func importingBackupRestoresSnapshotValues() async throws {
        let store = ClosetStore()
        let originalName = store.profile.name

        var modifiedSnapshot = MockClosetDashboard.sampleSnapshot
        modifiedSnapshot.profile.name = "Imported User"
        modifiedSnapshot.weather.location = "Shanghai"

        let document = LocalClosetBackupDocument(
            payload: LocalClosetBackupPayload(
                snapshot: modifiedSnapshot,
                images: [:],
                exportedAt: .now
            )
        )

        #expect(originalName != "Imported User")
        store.importBackup(document)

        #expect(store.profile.name == "Imported User")
        #expect(store.weather.location == "Shanghai")
    }

}
