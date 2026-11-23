//
//  LKAIChatInputTests.swift
//  LKAIKitCLITests
//
//  Created by Leo Ho on 2026/11/23.
//

import Foundation
import LKAIKit
import Testing

@testable import LKAIKitCLI

/// `LKAIChatInput` 與 `LKAIChatInputError` 的單元測試：請求怎麼組、提示詞與金鑰從哪裡來、
/// 十條輸入規則的檢查順序與訊息，以及逾時設定
///
/// - Note: 用 `InputArguments` 組出一組合法的輸入，每個測試只改要破壞或要檢查的那幾項
/// - Note: 需要檔案的測試各自建立暫存資料夾，結束時刪除，所以可以平行執行
struct LKAIChatInputTests {

    // MARK: - Properties

    /// 保證不存在的提示詞檔案路徑：暫存資料夾內、名稱是 UUID 而且不會建立的資料夾裡的 `missing.txt`
    ///
    /// - Note: 不用相對路徑：相對路徑會依測試行程的工作目錄解析，package 根目錄剛好有同名檔案時，
    ///   「檔案讀不了」的情境就不成立
    /// - Note: 整個行程只產生一次，所以同一次執行內，所有用到的測試資料都是同一個路徑
    private static let missingPromptFilePath = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        .appending(path: "missing.txt")
        .path

    // spectra-scenario: cli-chat / Build the request from the options
    /// 驗證依選項建立的輸入：模型原樣、只有一則使用者訊息、沒有系統指示、輸出上限照傳入的值，
    /// 供應商、金鑰與逾時也都是傳入的值
    ///
    /// - Note: 輸出上限的預設值 4096 與逾時的預設值 60 在 `LKAICommand` 宣告，
    ///   這裡只確認傳入的值原樣放進輸入
    @Test
    func init_依選項建立_請求只有一則使用者訊息且欄位原樣放入() throws {
        // Given
        let arguments = InputArguments(
            provider: .anthropic,
            model: "claude-opus-5-5",
            prompt: "Reply with OK.",
            apiKey: "sk-test",
            maxOutputTokens: 4096,
            timeout: 60
        )
        let expectedRequest = LKAIChatRequest(
            model: "claude-opus-5-5",
            messages: [LKAIMessage(role: .user, text: "Reply with OK.")],
            systemPrompt: nil,
            maxOutputTokens: 4096
        )

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.request == expectedRequest)
        #expect(input.provider == .anthropic)
        #expect(input.apiKey.unredactedValue == "sk-test")
        #expect(input.timeout == 60)
    }

    // spectra-scenario: cli-chat / Build the request from the options
    /// 驗證模型與提示詞不修剪、不改寫：前後的空白、純空白的模型、`-` 開頭的提示詞與換行都原樣放進請求
    ///
    /// - Parameters:
    ///   - model: `--model` 的值
    ///   - prompt: `--prompt` 的值
    /// - Note: 純空白的模型不算空字串，和 `LKAIChatRequest.validate()` 相同
    @Test(arguments: [
        (" x ", " hi \n"),
        (" ", "- item"),
        ("claude-opus-5-5", "line 1\nline 2\n"),
    ])
    func init_模型與提示詞含空白或換行_都原樣放進請求(model: String, prompt: String) throws {
        // Given
        let arguments = InputArguments(model: model, prompt: prompt, maxOutputTokens: 4096)
        let expectedRequest = LKAIChatRequest(
            model: model,
            messages: [LKAIMessage(role: .user, text: prompt)],
            systemPrompt: nil,
            maxOutputTokens: 4096
        )

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.request == expectedRequest)
    }

    /// 驗證輸出上限只要不小於 1，就原樣放進請求，1 是接受的下限
    ///
    /// - Parameter maxOutputTokens: `--max-output-tokens` 的值
    @Test(arguments: [1, 4096, 100_000])
    func init_輸出上限不小於1_原樣放進請求(maxOutputTokens: Int) throws {
        // Given
        let arguments = InputArguments(maxOutputTokens: maxOutputTokens)

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.request.maxOutputTokens == maxOutputTokens)
    }

    // spectra-scenario: cli-chat / Send the prompt file content unchanged
    /// 驗證提示詞檔案的內容原樣成為訊息文字，包含結尾的 LF（`\n`），不修剪
    @Test
    func init_提示詞檔案_訊息文字等於檔案內容且含結尾的LF() throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let fileContent = "# Title\nBody\n"
        let filePath = try writeFile(named: "prompt.md", content: fileContent, in: directory)
        let arguments = InputArguments(prompt: nil, promptFile: filePath)

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.request.messages == [LKAIMessage(role: .user, text: fileContent)])
    }

    // spectra-scenario: cli-chat / Check the prompt file extension
    // spectra-scenario: cli-chat / Check the prompt file extension / prompt file paths
    /// 驗證副檔名是 `txt` 或 `md`（不分大小寫）的檔案被接受，內容成為訊息文字
    ///
    /// - Parameter relativePath: 檔案在暫存資料夾內的相對路徑，對應範例表 accepted 的三列
    /// - Note: 檔案真的建立，內容不是空白，所以被接受只取決於副檔名
    @Test(arguments: ["notes.txt", "README.MD", "docs/plan.Md"])
    func init_副檔名是txt或md不分大小寫_接受檔案並讀出內容(relativePath: String) throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let filePath = try writeFile(named: relativePath, content: "Body\n", in: directory)
        let arguments = InputArguments(prompt: nil, promptFile: filePath)

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.request.messages == [LKAIMessage(role: .user, text: "Body\n")])
    }

    // spectra-scenario: cli-chat / Check the prompt file extension
    // spectra-scenario: cli-chat / Check the prompt file extension / prompt file paths
    /// 驗證副檔名不是 `txt` 或 `md` 的檔案被拒絕，錯誤帶著傳入的路徑
    ///
    /// - Parameter relativePath: 檔案在暫存資料夾內的相對路徑，對應範例表 rejected 的三列
    /// - Note: 檔案真的建立而且可讀，所以被拒絕只取決於副檔名
    @Test(arguments: ["prompt.markdown", "prompt", "prompt.txt.bak"])
    func init_副檔名不是txt或md_丟出unsupportedPromptFile帶傳入的路徑(relativePath: String) throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let filePath = try writeFile(named: relativePath, content: "Body\n", in: directory)
        let arguments = InputArguments(prompt: nil, promptFile: filePath)
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == .unsupportedPromptFile(path: filePath))
    }

    // spectra-scenario: cli-chat / Reject a blank prompt
    // spectra-scenario: cli-chat / Reject a blank prompt / blank prompt sources
    /// 驗證 `--prompt` 是空字串或只有空白與換行時，丟出不帶路徑的 `blankPrompt`，訊息在兩種語言都含 `--prompt`
    ///
    /// - Parameter prompt: `--prompt` 的值：範例表的空白、tab 與 LF（`\n`），以及空字串、CR（`\r`）加 LF
    @Test(arguments: [" \t\n ", "", "\r\n"])
    func init_prompt只有空白或換行_丟出blankPrompt且訊息含prompt選項(prompt: String) throws {
        // Given
        let arguments = InputArguments(prompt: prompt)
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == .blankPrompt(path: nil))
        for language in LKAIOutputLanguage.allCases {
            #expect(error.message(in: language).contains("--prompt"))
        }
    }

    // spectra-scenario: cli-chat / Reject a blank prompt
    // spectra-scenario: cli-chat / Reject a blank prompt / blank prompt sources
    /// 驗證提示詞檔案只有空白與 LF（`\n`）時，丟出帶檔案路徑的 `blankPrompt`，訊息在兩種語言都含檔名
    @Test
    func init_提示詞檔案只有空白與LF_丟出blankPrompt帶路徑且訊息含檔名() throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let filePath = try writeFile(named: "blank.md", content: "  \n \n", in: directory)
        let arguments = InputArguments(prompt: nil, promptFile: filePath)
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == .blankPrompt(path: filePath))
        for language in LKAIOutputLanguage.allCases {
            #expect(error.message(in: language).contains("blank.md"))
        }
    }

    // spectra-scenario: cli-chat / Choose the API key source
    // spectra-scenario: cli-chat / Choose the API key source / key sources for openai
    /// 驗證供應商是 openai 時，金鑰依範例表選出：`--apiKey` 不是空字串就用它，
    /// 否則用環境變數；兩者都沒有值就回報缺少金鑰，帶著環境變數的名稱
    ///
    /// - Parameter testCase: 一列範例：`--apiKey` 的值、環境變數，以及預期的金鑰或錯誤
    /// - Note: 前五列是範例表的寫法；最後一列是多加的：只設了別家的環境變數時，不能拿來用
    @Test(arguments: [
        KeySourceCase(
            apiKey: "sk-flag",
            environment: ["LKAI_OPENAI_API_KEY": "sk-env"],
            expectedKey: "sk-flag",
            expectedError: nil
        ),
        KeySourceCase(
            apiKey: nil,
            environment: ["LKAI_OPENAI_API_KEY": "sk-env"],
            expectedKey: "sk-env",
            expectedError: nil
        ),
        KeySourceCase(
            apiKey: "",
            environment: ["LKAI_OPENAI_API_KEY": "sk-env"],
            expectedKey: "sk-env",
            expectedError: nil
        ),
        KeySourceCase(
            apiKey: nil,
            environment: [:],
            expectedKey: nil,
            expectedError: .missingAPIKey(environmentName: "LKAI_OPENAI_API_KEY")
        ),
        KeySourceCase(
            apiKey: nil,
            environment: ["LKAI_OPENAI_API_KEY": ""],
            expectedKey: nil,
            expectedError: .missingAPIKey(environmentName: "LKAI_OPENAI_API_KEY")
        ),
        KeySourceCase(
            apiKey: nil,
            environment: ["LKAI_ANTHROPIC_API_KEY": "sk-other"],
            expectedKey: nil,
            expectedError: .missingAPIKey(environmentName: "LKAI_OPENAI_API_KEY")
        ),
    ])
    func init_金鑰來源_依範例表選出金鑰或回報缺少金鑰(testCase: KeySourceCase) {
        // Given
        let arguments = InputArguments(
            provider: .openai,
            apiKey: testCase.apiKey,
            environment: testCase.environment
        )
        var actualKey: String?
        var actualError: LKAIChatInputError?

        // When
        do {
            actualKey = try makeInput(arguments).apiKey.unredactedValue
        } catch {
            actualError = error
        }

        // Then
        #expect(actualKey == testCase.expectedKey)
        #expect(actualError == testCase.expectedError)
    }

    // spectra-scenario: cli-chat / Read the environment variable of the selected provider
    /// 驗證沒給 `--apiKey` 時，讀的是所選供應商的環境變數：三個環境變數同時有值而且各不相同，
    /// 取到的是該供應商的那一個
    ///
    /// - Parameters:
    ///   - provider: 所選的供應商
    ///   - expectedKey: 該供應商的環境變數的值
    @Test(arguments: [
        (.anthropic, "key-anthropic"),
        (.openai, "key-openai"),
        (.google, "key-gemini"),
    ] as [(LKAIChatProvider, String)])
    func init_沒給apiKey_讀所選供應商的環境變數(
        provider: LKAIChatProvider,
        expectedKey: String
    ) throws {
        // Given
        let environment = [
            "LKAI_ANTHROPIC_API_KEY": "key-anthropic",
            "LKAI_OPENAI_API_KEY": "key-openai",
            "LKAI_GEMINI_API_KEY": "key-gemini",
        ]
        let arguments = InputArguments(provider: provider, apiKey: nil, environment: environment)

        // When
        let input = try makeInput(arguments)

        // Then
        #expect(input.apiKey.unredactedValue == expectedKey)
    }

    // spectra-scenario: cli-chat / Configure the timeout
    // spectra-scenario: cli-chat / Configure the timeout / timeout values
    /// 驗證傳入的逾時秒數原樣成為 session 設定的請求逾時，1 是接受的下限
    ///
    /// - Parameters:
    ///   - timeout: `--timeout` 的值
    ///   - expectedInterval: 預期的請求逾時，單位為秒
    /// - Note: 預設的 60 秒在 `LKAICommand` 宣告，這裡只確認傳入的值原樣設定
    @Test(arguments: [(60, 60), (300, 300), (1, 1)] as [(Int, TimeInterval)])
    func makeSessionConfiguration_指定逾時_請求逾時等於該秒數(
        timeout: Int,
        expectedInterval: TimeInterval
    ) throws {
        // Given
        let input = try makeInput(InputArguments(timeout: timeout))

        // When
        let configuration = input.makeSessionConfiguration()

        // Then
        #expect(configuration.timeoutIntervalForRequest == expectedInterval)
    }

    // spectra-scenario: cli-chat / Report the first failing rule
    // spectra-scenario: cli-chat / Report the first failing rule / validation rules in order
    /// 驗證每條規則被破壞時，丟出該規則的錯誤，訊息在兩種語言都含範例表指定的詞，而且不含 API 金鑰
    ///
    /// - Parameter testCase: 一列範例：只破壞一條規則的輸入、預期的錯誤，以及訊息要含有的詞
    /// - Note: 範例表的十條規則各有一列，其他是多加的列：空字串的模型、提示詞是空字串時仍算
    ///   「兩個都給」、輸出上限與逾時為負數，以及另外兩家供應商缺少金鑰時，訊息要寫出各自的環境變數
    @Test(arguments: [
        RuleCase(
            arguments: InputArguments(provider: nil),
            expectedError: .missingProvider,
            expectedTokens: ["--provider"]
        ),
        RuleCase(
            arguments: InputArguments(model: nil),
            expectedError: .missingModel,
            expectedTokens: ["--model"]
        ),
        RuleCase(
            arguments: InputArguments(model: ""),
            expectedError: .missingModel,
            expectedTokens: ["--model"]
        ),
        RuleCase(
            arguments: InputArguments(promptFile: "a.txt"),
            expectedError: .conflictingPrompts,
            expectedTokens: ["--prompt-file"]
        ),
        RuleCase(
            arguments: InputArguments(prompt: "", promptFile: "a.txt"),
            expectedError: .conflictingPrompts,
            expectedTokens: ["--prompt-file"]
        ),
        RuleCase(
            arguments: InputArguments(prompt: nil),
            expectedError: .missingPrompt,
            expectedTokens: ["--prompt"]
        ),
        RuleCase(
            arguments: InputArguments(prompt: nil, promptFile: "a.json"),
            expectedError: .unsupportedPromptFile(path: "a.json"),
            expectedTokens: ["--prompt-file"]
        ),
        RuleCase(
            arguments: InputArguments(
                prompt: nil,
                promptFile: LKAIChatInputTests.missingPromptFilePath
            ),
            expectedError: .unreadablePromptFile(path: LKAIChatInputTests.missingPromptFilePath),
            expectedTokens: [LKAIChatInputTests.missingPromptFilePath]
        ),
        RuleCase(
            arguments: InputArguments(prompt: " "),
            expectedError: .blankPrompt(path: nil),
            expectedTokens: ["--prompt"]
        ),
        RuleCase(
            arguments: InputArguments(maxOutputTokens: 0),
            expectedError: .invalidMaxOutputTokens,
            expectedTokens: ["--max-output-tokens"]
        ),
        RuleCase(
            arguments: InputArguments(maxOutputTokens: -1),
            expectedError: .invalidMaxOutputTokens,
            expectedTokens: ["--max-output-tokens"]
        ),
        RuleCase(
            arguments: InputArguments(timeout: 0),
            expectedError: .invalidTimeout,
            expectedTokens: ["--timeout"]
        ),
        RuleCase(
            arguments: InputArguments(timeout: -1),
            expectedError: .invalidTimeout,
            expectedTokens: ["--timeout"]
        ),
        RuleCase(
            arguments: InputArguments(apiKey: nil),
            expectedError: .missingAPIKey(environmentName: "LKAI_OPENAI_API_KEY"),
            expectedTokens: ["--apiKey", "LKAI_OPENAI_API_KEY"]
        ),
        RuleCase(
            arguments: InputArguments(provider: .anthropic, apiKey: nil),
            expectedError: .missingAPIKey(environmentName: "LKAI_ANTHROPIC_API_KEY"),
            expectedTokens: ["--apiKey", "LKAI_ANTHROPIC_API_KEY"]
        ),
        RuleCase(
            arguments: InputArguments(provider: .google, apiKey: nil),
            expectedError: .missingAPIKey(environmentName: "LKAI_GEMINI_API_KEY"),
            expectedTokens: ["--apiKey", "LKAI_GEMINI_API_KEY"]
        ),
    ])
    func init_違反一條規則_丟出該規則的錯誤且訊息含指定的詞(testCase: RuleCase) throws {
        // Given
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(testCase.arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == testCase.expectedError)
        for language in LKAIOutputLanguage.allCases {
            let message = error.message(in: language)
            for token in testCase.expectedTokens {
                #expect(message.contains(token), "訊息沒有含 \(token)：\(message)")
            }
            #expect(!message.contains(InputArguments.defaultAPIKey))
        }
    }

    // spectra-scenario: cli-chat / Report the first failing rule
    // spectra-scenario: cli-chat / Report the first failing rule / validation rules in order
    /// 驗證提示詞檔案讀不了時，丟出帶傳入路徑的 `unreadablePromptFile`：檔案不存在、是資料夾、
    /// 內容不是 UTF-8，三種都算
    ///
    /// - Parameter file: 讀不了的檔案是哪一種
    @Test(arguments: UnreadableFile.allCases)
    func init_提示詞檔案讀不了_丟出unreadablePromptFile帶傳入的路徑(file: UnreadableFile) throws {
        // Given
        let directory = try LKAICommandTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) } // 清理失敗可忽略，因為只是暫存資料夾
        let filePath = try file.preparePath(in: directory)
        let arguments = InputArguments(prompt: nil, promptFile: filePath)
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == .unreadablePromptFile(path: filePath))
    }

    // spectra-scenario: cli-chat / Report the first failing rule
    /// 驗證同時破壞多條規則時，只回報排在最前面的那一條
    ///
    /// - Parameter testCase: 一列範例：同時破壞多條規則的輸入，以及排在最前面的那條規則的錯誤
    @Test(arguments: [
        OrderCase(
            arguments: InputArguments(provider: nil, model: nil),
            expectedError: .missingProvider
        ),
        OrderCase(
            arguments: InputArguments(provider: nil, maxOutputTokens: 0),
            expectedError: .missingProvider
        ),
        OrderCase(
            arguments: InputArguments(model: nil, prompt: nil),
            expectedError: .missingModel
        ),
        OrderCase(
            arguments: InputArguments(promptFile: "a.json"),
            expectedError: .conflictingPrompts
        ),
        OrderCase(
            arguments: InputArguments(prompt: nil, promptFile: "a.json", maxOutputTokens: 0),
            expectedError: .unsupportedPromptFile(path: "a.json")
        ),
        OrderCase(
            arguments: InputArguments(
                prompt: nil,
                promptFile: LKAIChatInputTests.missingPromptFilePath,
                maxOutputTokens: 0
            ),
            expectedError: .unreadablePromptFile(path: LKAIChatInputTests.missingPromptFilePath)
        ),
        OrderCase(
            arguments: InputArguments(prompt: " ", maxOutputTokens: 0),
            expectedError: .blankPrompt(path: nil)
        ),
        OrderCase(
            arguments: InputArguments(maxOutputTokens: 0, timeout: 0),
            expectedError: .invalidMaxOutputTokens
        ),
        OrderCase(
            arguments: InputArguments(apiKey: nil, maxOutputTokens: 0),
            expectedError: .invalidMaxOutputTokens
        ),
        OrderCase(
            arguments: InputArguments(apiKey: nil, timeout: 0),
            expectedError: .invalidTimeout
        ),
    ])
    func init_同時違反多條規則_只回報排在最前面的那一條(testCase: OrderCase) throws {
        // Given
        var actualError: LKAIChatInputError?

        // When
        do {
            _ = try makeInput(testCase.arguments)
        } catch {
            actualError = error
        }

        // Then
        let error = try #require(actualError)
        #expect(error == testCase.expectedError)
    }
}

// MARK: - Nested Types

extension LKAIChatInputTests {

    /// 組出 `LKAIChatInput` 的一組參數，預設是一組合法的輸入，每個測試只改要破壞或要檢查的那幾項
    struct InputArguments: Sendable {

        /// 預設輸入的 API 金鑰，訊息不能含有它
        static let defaultAPIKey = "sk-secret-123"

        /// `--provider` 的值
        var provider: LKAIChatProvider? = .openai

        /// `--model` 的值
        var model: String? = "x"

        /// `--prompt` 的值
        var prompt: String? = "hi"

        /// `--prompt-file` 的值
        var promptFile: String?

        /// `--apiKey` 的值
        var apiKey: String? = InputArguments.defaultAPIKey

        /// `--max-output-tokens` 的值
        var maxOutputTokens = 4096

        /// `--timeout` 的值
        var timeout = 60

        /// 目前行程的環境變數
        var environment: [String: String] = [:]
    }

    /// 金鑰來源的一列範例：`--apiKey` 的值與環境變數，以及預期選出的金鑰或預期的錯誤
    struct KeySourceCase: Sendable {

        /// `--apiKey` 的值；沒給為 nil
        let apiKey: String?

        /// 目前行程的環境變數
        let environment: [String: String]

        /// 預期選出的金鑰；預期失敗時為 nil
        let expectedKey: String?

        /// 預期的錯誤；預期成功時為 nil
        let expectedError: LKAIChatInputError?
    }

    /// 一條規則被破壞的一列範例：輸入、預期的錯誤，以及兩種語言的訊息都要含有的詞
    struct RuleCase: Sendable {

        /// 只破壞一條規則的輸入
        let arguments: InputArguments

        /// 預期的錯誤
        let expectedError: LKAIChatInputError

        /// 訊息要含有的詞，選項名稱、檔案路徑或環境變數名稱
        let expectedTokens: [String]
    }

    /// 同時破壞多條規則的一列範例：輸入，以及排在最前面的那條規則的錯誤
    struct OrderCase: Sendable {

        /// 同時破壞多條規則的輸入
        let arguments: InputArguments

        /// 預期的錯誤，來自排在最前面的那條規則
        let expectedError: LKAIChatInputError
    }

    /// 提示詞檔案讀不了的三種情況
    enum UnreadableFile: CaseIterable, Sendable {

        /// 路徑上沒有檔案
        case missing

        /// 路徑是資料夾
        case directory

        /// 檔案存在，但內容不是 UTF-8
        case notUTF8

        /// 在指定的資料夾內準備好這一種情況，回傳要交給 `--prompt-file` 的路徑
        ///
        /// - Parameter directory: 暫存資料夾
        /// - Returns: 檔案路徑；副檔名都是 `txt` 或 `md`，所以讀不了只取決於檔案本身
        /// - Throws: 建立資料夾或檔案失敗時丟出
        func preparePath(in directory: URL) throws -> String {
            switch self {
            case .missing:
                return directory.appending(path: "missing.txt").path

            case .directory:
                let folderURL = directory.appending(path: "folder.md", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
                return folderURL.path

            case .notUTF8:
                let fileURL = directory.appending(path: "binary.txt")
                try Data([0xFF, 0xFE, 0xFD]).write(to: fileURL)
                return fileURL.path
            }
        }
    }
}

// MARK: - Private Method

private extension LKAIChatInputTests {

    /// 以一組參數建立輸入，欄位一一對應 `LKAIChatInput` 的 `init`
    ///
    /// - Parameter arguments: 要交給 `init` 的參數
    /// - Returns: 檢查通過的輸入
    /// - Throws: 任何一條輸入規則不符時丟出 `LKAIChatInputError`
    func makeInput(_ arguments: InputArguments) throws(LKAIChatInputError) -> LKAIChatInput {
        try LKAIChatInput(
            provider: arguments.provider,
            model: arguments.model,
            prompt: arguments.prompt,
            promptFile: arguments.promptFile,
            apiKey: arguments.apiKey,
            maxOutputTokens: arguments.maxOutputTokens,
            timeout: arguments.timeout,
            environment: arguments.environment
        )
    }

    /// 在資料夾內寫入一個 UTF-8 文字檔，需要時一併建立上層資料夾
    ///
    /// - Parameters:
    ///   - relativePath: 檔案在資料夾內的相對路徑
    ///   - content: 檔案內容
    ///   - directory: 暫存資料夾
    /// - Returns: 檔案的完整路徑，要交給 `--prompt-file`
    /// - Throws: 建立資料夾或寫入失敗時丟出
    func writeFile(
        named relativePath: String,
        content: String,
        in directory: URL
    ) throws -> String {
        let fileURL = directory.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }
}
