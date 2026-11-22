//
//  LKAIErrorTestSupport.swift
//  LKAITestSupport
//
//  Created by Leo Ho on 2026/11/22.
//

import LKAICore

/// 錯誤的測試 helper，描述測試預期的錯誤並判斷實際丟出的錯誤是否符合，供各供應商的測試共用
package enum LKAIErrorTestSupport {

}

// MARK: - Nested Types

extension LKAIErrorTestSupport {

    /// 測試預期的錯誤結果：指定的錯誤，或只要求是無效回應且說明含指定的文字
    ///
    /// - Note: 刻意寫成巢狀型別，因為 `Testing` 模組有公開的 `Expectation`
    package enum Expectation: Sendable {

        /// 丟出的錯誤必須等於指定的錯誤
        ///
        /// - Parameter error: 預期的錯誤
        case error(LKAIError)

        /// 丟出的錯誤必須是無效回應，而且說明文字含全部指定的文字
        ///
        /// - Parameter containing: 說明文字必須含有的文字；傳空陣列表示不比對說明文字
        case invalidResponse(containing: [String])

        /// 判斷實際丟出的錯誤是否符合這個預期
        ///
        /// - Parameter error: 實際丟出的錯誤；沒有錯誤時為 nil
        /// - Returns: 符合時為 `true`；沒有錯誤一律不符合，預期沒有錯誤時請另外比對 `error == nil`
        package func matches(_ error: LKAIError?) -> Bool {
            guard let error else {
                return false
            }
            switch self {
            case .error(let expectedError):
                return error == expectedError

            case .invalidResponse(let fragments):
                guard case .invalidResponse(let reason) = error else {
                    return false
                }
                return fragments.allSatisfy { reason.contains($0) }
            }
        }
    }
}

// MARK: - Internal Method

extension LKAIErrorTestSupport {

    /// 判斷錯誤是不是無效回應錯誤，只看種類，不看說明文字
    ///
    /// - Parameter error: 要判斷的錯誤；沒有錯誤時為 nil
    /// - Returns: 是無效回應錯誤時為 `true`；沒有錯誤時為 `false`
    package static func isInvalidResponse(_ error: LKAIError?) -> Bool {
        Expectation.invalidResponse(containing: []).matches(error)
    }
}
