# Lidlight

讓 MacBook 合蓋後繼續運作的 macOS 選單列工具。介面使用英文。

- Automatic：插電時保持運作，電池供電時允許睡眠。
- Stay awake：電池供電時也保持運作；10% 低電量時允許睡眠。
- Allow sleep：恢復正常睡眠。
- 合蓋熄背光、同面板診斷與安全退出。

支援 macOS 12 以上與 Apple silicon / Intel。從本儲存庫 Releases 下載 Lidlight.pkg。此版本未有正式開發者簽章或 Apple 公證，macOS 可能阻擋安裝。請依自己的硬體驗證合蓋、拔電與背光恢復。

建置與測試方式見 [English README](README.md)。

Lidlight 是作者的原創 macOS 工具。

## 1.1 功能

- 定時清醒、自訂截止時間、單次清醒、簡報模式與等待程序完成。
- 指定 App、外接螢幕、每日／平日跨午夜排程規則。
- 可調低電量門檻、僅插電清醒、選擇性低電量通知。
- 全域快捷鍵、登入啟動、重啟模式、選單倒數與像素角色表情。
- 狀態原因、後續動作、最近 40 筆本機紀錄與電量下降估算。
- 關閉螢幕、鎖定繼續運作、恢復背光與背景服務復原。
- 可在 macOS「捷徑」的 Run Shell Script 呼叫 `/usr/local/bin/lidlight timer 60`。

手動 Allow sleep 暫停規則，Automatic 恢復規則；低電量與僅插電保護永遠優先。
App／程序／排程規則需要 Lidlight 持續執行；定時截止由服務執行。程序等待最多七天，避免程序無法追蹤時無限清醒。關閉螢幕依 macOS 設定可能鎖定；Lock & run 明確鎖定。通知啟用時才請求權限，預設不主動改變現有工作流程。
