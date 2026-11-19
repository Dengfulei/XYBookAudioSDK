# 本地二进制分发配置；远程发布前需将占位地址替换为真实的版本化下载地址。
Pod::Spec.new do |spec|
  spec.name = 'XYBookAudioSDK'
  spec.version = '1.0.0'
  spec.summary = 'Built-in listening WebView and native audiobook playback.'
  spec.homepage = 'https://example.invalid/XYBookAudioSDK'
  spec.license = { :type => 'Proprietary', :text => 'All rights reserved.' }
  spec.author = 'XYBookAudioSDK'
  spec.source = { :http => 'https://example.invalid/XYBookAudioSDK-1.0.0.zip' }
  spec.ios.deployment_target = '15.0'
  spec.vendored_frameworks = 'Products/Frameworks/XYBookAudioSDK.xcframework'
  spec.frameworks = 'UIKit', 'WebKit', 'AVFoundation', 'MediaPlayer'
  spec.dependency 'YYModel', '1.0.4'
end
