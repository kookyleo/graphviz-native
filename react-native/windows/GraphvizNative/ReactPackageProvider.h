/*
 * ReactPackageProvider.h (Windows)
 *
 * Registers the GraphvizModule with the React Native Windows runtime.
 *
 * Licensed under the Apache License, Version 2.0
 */

#pragma once

#include <winrt/Microsoft.ReactNative.h>

namespace winrt::GraphvizNative::implementation {

struct ReactPackageProvider
    : winrt::implements<ReactPackageProvider, winrt::Microsoft::ReactNative::IReactPackageProvider> {

    void CreatePackage(winrt::Microsoft::ReactNative::IReactPackageBuilder const& packageBuilder) noexcept;
};

} // namespace winrt::GraphvizNative::implementation
