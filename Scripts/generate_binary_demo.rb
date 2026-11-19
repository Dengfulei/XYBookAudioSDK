# 生成独立二进制接入工程，不引入 SDK target、实现源码或依赖开发仓库相对路径的 framework。
require 'xcodeproj'
root = File.expand_path(ARGV.fetch(0))
project = Xcodeproj::Project.new(File.join(root, 'XYBookAudioSDKDemo.xcodeproj'))
app = project.new_target(:application, 'XYBookAudioSDKDemo', :ios, '15.0')
group = project.main_group.new_group('Sources', 'Sources')
Dir.glob(File.join(root, 'Sources', '**', '*.{h,m,swift,storyboard}')).sort.each do |path|
  app.add_file_references([group.new_file(path.delete_prefix(File.join(root, 'Sources') + '/'))])
end
fixture = project.main_group.new_file('Fixture')
fixture.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(fixture)
app.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.codexai.bookaudio.binarydemo',
    'INFOPLIST_FILE' => 'Sources/Info.plist', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_UILaunchStoryboardName' => 'LaunchScreen', 'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ENABLE_OBJC_ARC' => 'YES', 'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO', 'CODE_SIGN_STYLE' => 'Automatic',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks']
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
# xcodeproj 默认只配置构建，需要显式指定 Run 和 Profile 启动的应用。
scheme.configure_with_targets(app, nil, launch_target: true)
scheme.save_as(project.path, 'XYBookAudioSDKDemo', true)
