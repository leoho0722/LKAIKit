//
//  LKAITestWaiting.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/22.
//

/// 測試用的等待 helper，供各供應商的測試共用
package enum LKAITestWaiting {

}

// MARK: - Internal Method

extension LKAITestWaiting {

    /// 最多等 2 秒，每 10 毫秒檢查一次條件，條件成立就立刻返回；取消是非同步的，所以要等替身偵測到
    ///
    /// - Parameter condition: 要等它成立的條件
    /// - Throws: 測試的 task 在等待中被取消時丟出
    /// - Note: 條件一直沒有成立時，等滿就返回，由呼叫端接著的斷言失敗
    package static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
