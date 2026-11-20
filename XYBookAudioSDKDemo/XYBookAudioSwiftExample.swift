// 仅依赖公开模块编译，验证 Swift 导入及听书页面展示接口的可用性。
import UIKit
import XYBookAudioSDK

@MainActor enum XYBookAudioSwiftExample {
    static func make(host: XYBookAudioHost, entryURL: URL) throws -> XYBookAudioSDKManager {
        let configuration = XYBookAudioConfiguration(hostIdentifier: "swift-host", entryURL: entryURL)
        #if DEBUG
            // 日志配置随 SDK 实例复制，Release 保持默认关闭。
            configuration.logLevel = .debug
        #endif
        return try XYBookAudioSDKManager(configuration: configuration, host: host)
    }

    static func open(
        _ sdk: XYBookAudioSDKManager, from presenter: UIViewController,
        style: XYBookAudioOpenStyle = .present,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        sdk.open(from: presenter, style: style, completion: completion)
    }
}
