//
//  LKAIOutputLanguage.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/23.
//

/// `lkai` 自己輸出的文字使用的語言，由 `--output-language` 選項決定
///
/// - Note: 只有 `en-US` 與 `zh-TW` 兩種，說明、輸入錯誤與警告都依它查 `LKAIKitCLI` 的 String Catalog
/// - Note: 不依賴 ArgumentParser，與命令列解析的對接只寫在 `LKAICommand.swift`
enum LKAIOutputLanguage: String, CaseIterable, Sendable {

    /// 英文，沒有給 `--output-language` 時的預設語言
    case enUS = "en-US"

    /// 正體中文
    case zhTW = "zh-TW"

    // MARK: - Properties

    /// 這次執行的輸出語言；沒有綁定時是 `.enUS`
    ///
    /// - Note: 用 `$current.withValue(_:operation:)` 在作用域內綁定，不直接賦值
    /// - Note: 說明與解析階段的文字產生時，沒有地方可以傳入語言，所以讀這個值
    /// - Note: 只給說明與解析階段讀；解析之後一律用解析出的 `outputLanguage`，不讀這個值
    @TaskLocal static var current: LKAIOutputLanguage = .enUS
}

// MARK: - Computed Properties

extension LKAIOutputLanguage {

    /// 對應 String Catalog 的語言資料夾名稱，不含 `.lproj`：`en-US` 是 `en`，`zh-TW` 是 `zh-Hant`
    var localization: String {
        switch self {
        case .enUS:
            "en"

        case .zhTW:
            "zh-Hant"
        }
    }
}

// MARK: - Internal Method

extension LKAIOutputLanguage {

    /// 從原始命令列引數掃描出這次執行的輸出語言，規則和 swift-argument-parser 解析 `--output-language` 一致
    ///
    /// - Parameter arguments: 命令列引數，不含執行檔的名稱
    /// - Returns: 取最後一次出現的值；沒有給選項、任何一次出現的值不合法，或 `--output-language`
    ///   是最後一個引數而沒有值時為 `.enUS`
    /// - Note: 支援 `--output-language <值>` 與 `--output-language=<值>`，只看 `--` 之前的引數
    /// - Note: 以 `LKAIOutputLanguage(rawValue:)` 判斷，大小寫要完全相同，所以 `zh-tw` 不合法
    /// - Note: 值不合法時解析器會以退出碼 64 拒絕這次輸入，那次執行的所有文字都用 `.enUS`
    /// - Note: 說明與解析錯誤的文字在解析之前就要產生，等不到解析器的結果，所以要自己先掃描
    /// - Note: 下列情況要跟著修改這個方法，否則掃描的結果和解析器不同：為 `--output-language`
    ///   加任何其他名稱（短名稱或第二個長名稱）、自訂 `init?(argument:)`（例如不分大小寫，
    ///   或接受別名）、改變任一選項的 parsing 策略、加位置引數或子指令；加子指令時，
    ///   `--output-language` 要以 `@OptionGroup` 讓每個子指令都接受
    static func scanned(from arguments: [String]) -> LKAIOutputLanguage {
        let optionName = "--output-language"
        let assignmentPrefix = "\(optionName)="
        var scannedLanguage: LKAIOutputLanguage?
        var remainingArguments = arguments.makeIterator()
        while let argument = remainingArguments.next() {
            if argument == "--" {
                break
            }
            let value: String?
            if argument == optionName {
                value = remainingArguments.next()
            } else if argument.hasPrefix(assignmentPrefix) {
                value = String(argument.dropFirst(assignmentPrefix.count))
            } else {
                continue
            }
            // 任何一次出現的值不合法，或選項後面沒有值，整次都用英文，不必再往後看
            guard let value, let language = LKAIOutputLanguage(rawValue: value) else {
                return .enUS
            }
            scannedLanguage = language
        }
        return scannedLanguage ?? .enUS
    }
}
