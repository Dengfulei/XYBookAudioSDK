# 原地更新现有工程，保留原生 target 标识和用户的签名配置。
require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'XYBookAudioSDK.xcodeproj'))
framework = project.targets.find { |target| target.name == 'XYBookAudioSDK' }
demo = project.targets.find { |target| target.name == 'XYBookAudioSDKDemo' }
tests = project.targets.find { |target| target.name == 'XYBookAudioSDKTests' } || project.new_target(:unit_test_bundle, 'XYBookAudioSDKTests', :ios, '15.0')
host = project.targets.find { |target| target.name == 'XYBookAudioSDKTestHost' } || project.new_target(:application, 'XYBookAudioSDKTestHost', :ios, '15.0')
host.product_reference.path = 'XYBookAudioSDKTestHost.app'
tests.product_reference.path = 'XYBookAudioSDKTests.xctest'
project.build_configurations.each do |configuration|
  configuration.build_settings.delete('MACH_O_TYPE')
  configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  configuration.build_settings['ONLY_ACTIVE_ARCH'] = configuration.name == 'Debug' ? 'YES' : 'NO'
end
# CocoaPods 嵌入脚本需要复制依赖包；启用 Xcode 用户脚本沙盒会阻止其 rsync 操作。
[framework, demo, tests, host].each do |target|
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!({
      'PRODUCT_NAME' => '$(TARGET_NAME)', 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0', 'CLANG_ENABLE_OBJC_ARC' => 'YES', 'CLANG_ENABLE_MODULES' => 'YES',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO', 'TARGETED_DEVICE_FAMILY' => '1,2', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'DEBUG_INFORMATION_FORMAT' => 'dwarf-with-dsym', 'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
    })
  end
end
framework.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'MACH_O_TYPE' => 'mh_dylib', 'SKIP_INSTALL' => 'NO', 'DEFINES_MODULE' => 'YES',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES', 'VERSIONING_SYSTEM' => 'apple-generic',
    'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '1.0.0',
    'DYLIB_CURRENT_VERSION' => '1', 'DYLIB_COMPATIBILITY_VERSION' => '1',
    'HEADER_SEARCH_PATHS' => ['$(inherited)', '$(SRCROOT)/XYBookAudioSDK/**']
  })
end
demo.build_configurations.each do |configuration|
  configuration.build_settings.merge!({'MACH_O_TYPE' => 'mh_execute', 'SWIFT_VERSION' => '5.0', 'SWIFT_OBJC_BRIDGING_HEADER' => ''})
end
framework.file_system_synchronized_groups.each do |group|
  group.exceptions.each do |exception|
    exception.public_headers = %w[XYBookAudioSDK.h XYBookAudioSDKManager.h XYBookAudioHost.h XYBookAudioTypes.h] if exception.target == framework
  end
end
# 测试使用空白应用作为宿主，避免 Demo 启动和模拟账号影响 SDK 状态。
group = project.main_group.find_subpath('Tests', true)
group.path = 'Tests'
Dir.glob(File.join(root, 'Tests', '*.m')).sort.each do |path|
  ref = group.files.find { |file| file.path == File.basename(path) } || group.new_file(File.basename(path))
  tests.add_file_references([ref]) unless tests.source_build_phase.files_references.include?(ref)
end
# 在现有 XCTest 中验证真实宿主接入层，不新增测试 target，也不把示例代码编入 framework。
host_integration = group.find_subpath('HostIntegrationSources', true)
host_integration.path = '../XYBookAudioSDKDemo'
Dir.glob(File.join(root, 'XYBookAudioSDKDemo', '{BookAudio,Account}', '*.{h,m}')).sort.each do |path|
  relative = path.delete_prefix(File.join(root, 'XYBookAudioSDKDemo') + '/')
  ref = host_integration.files.find { |file| file.path == relative } || host_integration.new_file(relative)
  tests.add_file_references([ref]) if File.extname(path) == '.m' && !tests.source_build_phase.files_references.include?(ref)
end
host_ref = group.files.find { |file| file.path == 'Host/main.m' } || group.new_file('Host/main.m')
host.add_file_references([host_ref]) unless host.source_build_phase.files_references.include?(host_ref)
resources = project.main_group.find_subpath('DemoResources', true)
resources.path = 'DemoResources'
fixture = resources.files.find { |file| file.path == 'Fixture' } || resources.new_file('Fixture')
fixture.last_known_file_type = 'folder'
[demo, tests].each { |target| target.resources_build_phase.add_file_reference(fixture, true) }
[demo, host, tests].each do |target|
  target.add_dependency(framework) unless target.dependencies.any? { |dependency| dependency.target == framework }
  target.frameworks_build_phase.add_file_reference(framework.product_reference, true)
end
tests.add_dependency(host) unless tests.dependencies.any? { |dependency| dependency.target == host }
embed = host.copy_files_build_phases.find { |phase| phase.name == 'Embed Frameworks' } || host.new_copy_files_build_phase('Embed Frameworks')
embed.dst_subfolder_spec = '10'
embed.add_file_reference(framework.product_reference, true).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
host.build_configurations.each do |configuration|
  configuration.build_settings.merge!({'MACH_O_TYPE' => 'mh_execute', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.codexai.bookaudio.testhost', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES'})
end
tests.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'MACH_O_TYPE' => 'mh_bundle', 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.codexai.bookaudio.tests',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/XYBookAudioSDKTestHost.app/XYBookAudioSDKTestHost',
    'BUNDLE_LOADER' => '$(TEST_HOST)', 'HEADER_SEARCH_PATHS' => ['$(inherited)', '$(SRCROOT)/XYBookAudioSDK/**']
  })
end
aggregate = project.targets.find { |target| target.name == 'XYBookAudioSDKPackage' }
aggregate.shell_script_build_phases.first.shell_script = 'env -u TARGET_BUILD_DIR -u SDKROOT bash "${SRCROOT}/Scripts/package.sh"' if aggregate
aggregate.build_configurations.each { |configuration| configuration.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO' } if aggregate
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(framework)
scheme.add_test_target(tests)
scheme.save_as(project.path, 'XYBookAudioSDK', true)
scheme = Xcodeproj::XCScheme.new
# xcodeproj 默认只配置构建，需要显式指定 Run 和 Profile 启动的应用。
scheme.configure_with_targets(demo, nil, launch_target: true)
scheme.save_as(project.path, 'XYBookAudioSDKDemo', true)
