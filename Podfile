platform :ios, '27.0'

target 'Lectigo' do
  use_frameworks!

  pod 'onnxruntime-objc', '~> 1.24'
  pod 'Yams', '~> 5.0'
  pod 'OpenCV', '~> 4.3.0'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '27.0'
      end
    end
  end
end