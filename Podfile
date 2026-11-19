# SDK 与接入宿主共同解析并使用同一份外部动态 YYModel 依赖。
source 'https://cdn.cocoapods.org/'
platform :ios, '15.0'
use_frameworks! :linkage => :dynamic
abstract_target 'commonPods' do
  pod 'YYModel', '1.0.4'
  target 'XYBookAudioSDK' do
    target 'XYBookAudioSDKTests' do
      inherit! :search_paths
    end
  end
  target 'XYBookAudioSDKDemo' do
  end
  target 'XYBookAudioSDKTestHost' do
  end
end
# YYModel 上游声明的最低系统版本早于本工程支持的 Xcode 和 iOS 范围。
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
