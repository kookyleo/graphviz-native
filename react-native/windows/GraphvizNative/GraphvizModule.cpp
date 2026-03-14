/*
 * GraphvizModule.cpp (Windows)
 *
 * C++/WinRT React Native module implementation for Windows.
 * Manages a singleton Graphviz context with mutex-protected access.
 * Promise resolution dispatches work via the thread pool.
 *
 * Licensed under the Apache License, Version 2.0
 */

#include "GraphvizModule.h"

#include <thread>
#include <cstring>

namespace GraphvizNative {

static const char kBase64Table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

GraphvizModule::GraphvizModule() : m_context(nullptr) {}

GraphvizModule::~GraphvizModule() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_context) {
        gv_context_free(m_context);
        m_context = nullptr;
    }
}

gv_context_t* GraphvizModule::ensureContext() {
    // Caller must hold m_mutex
    if (!m_context) {
        m_context = gv_context_new();
    }
    return m_context;
}

std::string GraphvizModule::errorCodeToString(gv_error_t err) {
    switch (err) {
        case GV_ERR_NULL_INPUT:       return "NULL_INPUT";
        case GV_ERR_INVALID_DOT:      return "INVALID_DOT";
        case GV_ERR_LAYOUT_FAILED:    return "LAYOUT_FAILED";
        case GV_ERR_RENDER_FAILED:    return "RENDER_FAILED";
        case GV_ERR_INVALID_ENGINE:   return "INVALID_ENGINE";
        case GV_ERR_INVALID_FORMAT:   return "INVALID_FORMAT";
        case GV_ERR_OUT_OF_MEMORY:    return "OUT_OF_MEMORY";
        case GV_ERR_NOT_INITIALIZED:  return "NOT_INITIALIZED";
        default:                      return "UNKNOWN";
    }
}

bool GraphvizModule::isTextFormat(const std::string& format) {
    return format == "svg" ||
           format == "json" ||
           format == "dot" ||
           format == "xdot" ||
           format == "plain";
}

std::string GraphvizModule::base64Encode(const char* data, size_t length) {
    std::string output;
    size_t olen = 4 * ((length + 2) / 3);
    output.resize(olen);

    size_t i = 0, j = 0;
    while (i < length) {
        uint32_t a = i < length ? static_cast<uint8_t>(data[i++]) : 0;
        uint32_t b = i < length ? static_cast<uint8_t>(data[i++]) : 0;
        uint32_t c = i < length ? static_cast<uint8_t>(data[i++]) : 0;
        uint32_t triple = (a << 16) | (b << 8) | c;

        output[j++] = kBase64Table[(triple >> 18) & 0x3F];
        output[j++] = kBase64Table[(triple >> 12) & 0x3F];
        output[j++] = kBase64Table[(triple >> 6) & 0x3F];
        output[j++] = kBase64Table[triple & 0x3F];
    }

    size_t mod = length % 3;
    if (mod == 1) {
        output[olen - 1] = '=';
        output[olen - 2] = '=';
    } else if (mod == 2) {
        output[olen - 1] = '=';
    }

    return output;
}

void GraphvizModule::renderDot(
    std::string dot,
    std::string engine,
    std::string format,
    React::ReactPromise<std::string> promise) noexcept {

    // Dispatch to a worker thread to avoid blocking the JS thread
    std::thread([this, dot = std::move(dot), engine = std::move(engine),
                 format = std::move(format), promise = std::move(promise)]() mutable {
        std::lock_guard<std::mutex> lock(m_mutex);

        gv_context_t* ctx = ensureContext();
        if (!ctx) {
            promise.Reject(React::ReactError{
                "NOT_INITIALIZED",
                "Failed to initialize Graphviz context"
            });
            return;
        }

        char* outData = nullptr;
        size_t outLength = 0;

        gv_error_t err = gv_render(
            ctx,
            dot.c_str(),
            engine.c_str(),
            format.c_str(),
            &outData,
            &outLength
        );

        if (err != GV_OK) {
            std::string code = errorCodeToString(err);
            const char* msg = gv_strerror(err);
            promise.Reject(React::ReactError{
                code,
                msg ? std::string(msg) : "Unknown error"
            });
            if (outData) {
                gv_free_render_data(outData);
            }
            return;
        }

        std::string result;
        if (isTextFormat(format)) {
            result = std::string(outData, outLength);
        } else {
            result = base64Encode(outData, outLength);
        }

        gv_free_render_data(outData);
        promise.Resolve(result);
    }).detach();
}

void GraphvizModule::getVersion(React::ReactPromise<std::string> promise) noexcept {
    const char* version = gv_version();
    if (version) {
        promise.Resolve(std::string(version));
    } else {
        promise.Reject(React::ReactError{
            "UNKNOWN",
            "Failed to get Graphviz version"
        });
    }
}

} // namespace GraphvizNative
