# 原版前端交互库测试资源

来源：参考工程随 XCTest 分发的 `xinhua-sdk`，版本 `1.15.8`。`xinhua-sdk.js` 保持原始字节，随附原 `package.json`，保留来源版本、作者及许可信息，库内注释原样保留。

SHA256：`10122c83965272939ae2c2849589b4af12b4ac9ee5c13891b597c58397de208f`。

仅作为现有 XCTest target 的资源，在真实 WKWebView 中验证标准 API，不通过重写消息构造器模拟标准。不会复制进 framework 或作为生产依赖。更新参考版本时，应同步来源说明、哈希和兼容性测试。
