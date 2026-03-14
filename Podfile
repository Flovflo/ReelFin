source 'https://cdn.cocoapods.org/'

install! 'cocoapods', deterministic_uuids: false
use_frameworks!

project 'ReelFin.xcodeproj'

target 'PlaybackEngine' do
  platform :ios, '26.0'
  pod 'MobileVLCKit', '~> 3.7.3'
end

target 'ReelFinApp' do
  platform :ios, '26.0'
  pod 'MobileVLCKit', '~> 3.7.3'
end

target 'ReelFinUI' do
  platform :ios, '26.0'
  pod 'MobileVLCKit', '~> 3.7.3'
end

target 'PlaybackEngineTV' do
  platform :tvos, '26.0'
  pod 'TVVLCKit', '~> 3.7.3'
end

target 'ReelFinTVApp' do
  platform :tvos, '26.0'
  pod 'TVVLCKit', '~> 3.7.3'
end

target 'ReelFinUITV' do
  platform :tvos, '26.0'
  pod 'TVVLCKit', '~> 3.7.3'
end

target 'PlaybackEngineTests' do
  platform :ios, '26.0'
  inherit! :search_paths
end
