"""打包二进制、公开文档和接入示例应用，不包含 framework 实现源码与构建缓存。"""
import os
from pathlib import Path
import shutil
import subprocess

project = Path(__file__).resolve().parents[1]
products = project / 'Products'
release = project / 'build/Distribution/XYBookAudioSDK-1.0.0'
if release.exists():
    shutil.rmtree(release)
release.mkdir(parents=True)
shutil.copytree(products / 'Frameworks', release / 'Frameworks')
shutil.copy2(products / 'DEPENDENCIES.txt', release / 'DEPENDENCIES.txt')
shutil.copytree(project / 'Docs', release / 'Docs')
specification = (project / 'XYBookAudioSDK.podspec').read_text()
(release / 'XYBookAudioSDK.podspec').write_text(specification.replace('Products/Frameworks/', 'Frameworks/'))
demo = release / 'Demo'
shutil.copytree(project / 'XYBookAudioSDKDemo', demo / 'Sources', ignore=shutil.ignore_patterns('*.xcassets'))
shutil.copytree(project / 'DemoResources/Fixture', demo / 'Fixture')
(demo / 'Podfile').write_text("platform :ios, '15.0'\n"
    "target 'XYBookAudioSDKDemo' do\n  pod 'XYBookAudioSDK', :path => '..'\nend\n")
# 使用当前 Ruby 环境，允许发布机器选择已安装 xcodeproj 的 Ruby。
ruby = os.environ.get('XYBOOK_RUBY', 'ruby')
subprocess.run([ruby, str(project / 'Scripts/generate_binary_demo.rb'), str(demo)], check=True)
(release / 'README.md').write_text('# XYBookAudioSDK 1.0.0\n\n'
    '独立二进制发行包，最低 iOS 15。framework 内置听书 WebView 和原生播放器。\n\n'
    '接入说明见 [Docs/HostIntegration.md](Docs/HostIntegration.md)。\n\n'
    '运行示例：`cd Demo && pod install --no-repo-update`，然后打开 `XYBookAudioSDKDemo.xcworkspace`。\n\n'
    '示例通过 CocoaPods 加载发行包内的 SDK 二进制。\n')
subprocess.run(['python3', str(project / 'Scripts/checksums.py'), str(release)], check=True)
print(shutil.make_archive(str(products / 'XYBookAudioSDK-1.0.0'), 'zip', release.parent, release.name))
