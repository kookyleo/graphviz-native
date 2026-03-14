/*
 * GraphvizModule.h (Windows)
 *
 * C++/WinRT React Native module for Graphviz rendering on Windows.
 * Uses the react-native-windows native module API.
 *
 * Licensed under the Apache License, Version 2.0
 */

#pragma once

#include <functional>
#include <string>
#include <mutex>

#include <NativeModules.h>

extern "C" {
#include "graphviz_api.h"
}

namespace GraphvizNative {

REACT_MODULE(GraphvizModule, L"GraphvizNative")
struct GraphvizModule {

    GraphvizModule();
    ~GraphvizModule();

    REACT_METHOD(renderDot, L"renderDot")
    void renderDot(
        std::string dot,
        std::string engine,
        std::string format,
        React::ReactPromise<std::string> promise) noexcept;

    REACT_METHOD(getVersion, L"getVersion")
    void getVersion(React::ReactPromise<std::string> promise) noexcept;

private:
    gv_context_t* ensureContext();

    gv_context_t* m_context;
    std::mutex m_mutex;

    static std::string errorCodeToString(gv_error_t err);
    static bool isTextFormat(const std::string& format);
    static std::string base64Encode(const char* data, size_t length);
};

} // namespace GraphvizNative
