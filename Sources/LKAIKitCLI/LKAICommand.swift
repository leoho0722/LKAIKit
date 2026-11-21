//
//  LKAICommand.swift
//  LKAIKitCLI
//
//  Created by Leo Ho on 2026/11/21.
//

import ArgumentParser
import LKAIKit

/// `lkai` 命令列工具的根指令，給 CI/CD 流程呼叫；目前沒有子指令與自訂選項，不帶參數時印出說明
@main
struct LKAICommand {

}

// MARK: - AsyncParsableCommand

extension LKAICommand: AsyncParsableCommand {

    /// 指令的名稱、簡介與版本；版本直接讀 `LKAIKitInfo.version`，不另存一份
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "lkai",
            abstract: "LKAIKit command-line tool for CI/CD workflows.",
            version: LKAIKitInfo.version
        )
    }
}
