require "json"

package = JSON.parse(File.read(File.join(__dir__, "..", "package.json")))

Pod::Spec.new do |s|
  s.name         = "GraphvizNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["repository"]["url"]
  s.license      = package["license"]
  s.authors      = package["author"]
  s.source       = { :git => package["repository"]["url"], :tag => s.version }

  s.ios.deployment_target = "15.1"
  s.osx.deployment_target = "11.0"

  s.source_files = "*.{h,m,mm}", "../src/*.{h,c}"
  s.public_header_files = "GraphvizModule.h"

  # Link against the prebuilt Graphviz static/shared libraries
  s.preserve_paths = "../third_party/graphviz/**"
  s.xcconfig = {
    "HEADER_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/../src\"",
    "LIBRARY_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/../third_party/graphviz/lib\"",
  }
  s.libraries = "graphviz_api"

  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"
  end
end
