//
//  LKAIKitInfo.swift
//  LKAICore
//
//  Created by Leo Ho on 2026/11/21.
//

/// LKAIKit 套件本身的資訊，目前只有版本號
public enum LKAIKitInfo {

    // MARK: - Properties

    /// 套件目前的版本號，格式固定為 `MAJOR.MINOR.PATCH`，不加 v 前綴
    ///
    /// - Note: 發佈新版時手動更新這個值
    /// - Note: 命令列工具的 `--version` 與日後送出的網路請求都讀這個值，確保版本一致
    public static let version: String = "0.1.0"
}
