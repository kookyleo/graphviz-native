/*
 * ReactPackageProvider.cpp (Windows)
 *
 * Registers the GraphvizModule with the React Native Windows runtime.
 *
 * Licensed under the Apache License, Version 2.0
 */

#include "ReactPackageProvider.h"

#include <NativeModules.h>

namespace winrt::GraphvizNative::implementation {

void ReactPackageProvider::CreatePackage(
    winrt::Microsoft::ReactNative::IReactPackageBuilder const& packageBuilder) noexcept {
    AddAttributedModules(packageBuilder, true);
}

} // namespace winrt::GraphvizNative::implementation
