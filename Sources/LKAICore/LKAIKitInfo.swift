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
    /// - Note: 這個值由 release workflow 更新：AI 回答升級等級，script 計算出新版號，再 commit 回
    ///   `main`；平常不必手動修改
    /// - Note: 要指定版號時，在 PR 中改成還沒有 tag、而且比所有 tag 都大的版號，合併後照原樣發佈；
    ///   細節見 `docs/releasing.md`
    /// - Note: 發版 script 以固定的寫法讀寫下面那一行：整行只有
    ///   `public static let version: String = "<版號>"`，而且整個檔案剛好一行。
    ///   寫法改變時，要一起修改 `.github/scripts/release/package-version.sh`；
    ///   發版 script 的測試以這個檔案建立暫存 repo，寫法不合時 CI 會失敗
    /// - Note: 命令列工具的 `--version` 與日後送出的網路請求都讀這個值，確保版本一致
    public static let version: String = "0.1.1"
}
