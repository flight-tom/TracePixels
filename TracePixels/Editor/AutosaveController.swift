import Combine
import Foundation
import os
import TracePixelsCore

/// 編輯內容持續自動保存（FR-022）：變更後 0.5 秒去抖動寫入資料庫；視窗關閉與結束應用程式時同步保存。
/// 保存失敗不阻擋操作，只在編輯器顯示提示並持續重試。
@MainActor
final class AutosaveController {
    private let viewModel: EditorViewModel
    private let library: LibraryStore
    private let log = Logger(subsystem: "com.tracepixels.app", category: "autosave")
    private var subscription: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var lastSaved: Capture

    init(viewModel: EditorViewModel, library: LibraryStore) {
        self.viewModel = viewModel
        self.library = library
        lastSaved = viewModel.capture
        subscription = viewModel.$document
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.save() }
            }
    }

    /// 立刻保存目前內容（視窗關閉、結束應用程式時使用）。
    func flush() async {
        retryTask?.cancel()
        await save()
    }

    private func save() async {
        let capture = viewModel.capture
        guard capture != lastSaved else { return }
        do {
            try await library.save(capture)
            lastSaved = capture
            viewModel.saveWarning = nil
            retryTask?.cancel()
        } catch {
            log.error("自動保存失敗：\(error.localizedDescription, privacy: .public)")
            viewModel.saveWarning = String(localized: "尚未保存，將自動重試")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }
}
