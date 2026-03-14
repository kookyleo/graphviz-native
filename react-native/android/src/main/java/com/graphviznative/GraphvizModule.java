/*
 * GraphvizModule.java
 *
 * React Native native module for Android.
 * Manages a singleton Graphviz context and dispatches rendering
 * to a background thread to keep the JS thread responsive.
 *
 * Licensed under the Apache License, Version 2.0
 */

package com.graphviznative;

import android.util.Base64;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class GraphvizModule extends ReactContextBaseJavaModule {

    private static final String TAG = "GraphvizNative";
    private static final String MODULE_NAME = "GraphvizNative";

    private static final Set<String> TEXT_FORMATS = new HashSet<>(
        Arrays.asList("svg", "json", "dot", "xdot", "plain")
    );

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private long contextPtr = 0;

    static {
        System.loadLibrary("graphviz_api");
    }

    public GraphvizModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    @NonNull
    public String getName() {
        return MODULE_NAME;
    }

    @Override
    public void invalidate() {
        if (contextPtr != 0) {
            nativeContextFree(contextPtr);
            contextPtr = 0;
        }
        executor.shutdown();
        super.invalidate();
    }

    /**
     * Lazily create the native context. Must be called from the executor thread.
     */
    private synchronized long ensureContext() {
        if (contextPtr == 0) {
            contextPtr = nativeContextNew();
            if (contextPtr == 0) {
                Log.e(TAG, "Failed to create Graphviz context");
            }
        }
        return contextPtr;
    }

    @ReactMethod
    public void renderDot(String dot, String engine, String format, Promise promise) {
        executor.execute(() -> {
            try {
                long ctx = ensureContext();
                if (ctx == 0) {
                    promise.reject("NOT_INITIALIZED", "Failed to initialize Graphviz context");
                    return;
                }

                String[] result = new String[1];
                int err = nativeRender(ctx, dot, engine, format, result);

                if (err != 0) {
                    String code = errorCodeToString(err);
                    String message = nativeStrerror(err);
                    promise.reject(code, message);
                    return;
                }

                if (result[0] == null) {
                    promise.reject("RENDER_FAILED", "Render returned null output");
                    return;
                }

                // For text formats, return as-is; for binary formats, already base64 from JNI
                promise.resolve(result[0]);

            } catch (Exception e) {
                Log.e(TAG, "Render failed with exception", e);
                promise.reject("UNKNOWN", "Unexpected error: " + e.getMessage());
            }
        });
    }

    @ReactMethod
    public void getVersion(Promise promise) {
        try {
            String version = nativeVersion();
            promise.resolve(version);
        } catch (Exception e) {
            promise.reject("UNKNOWN", "Failed to get version: " + e.getMessage());
        }
    }

    private static String errorCodeToString(int err) {
        switch (err) {
            case -1: return "NULL_INPUT";
            case -2: return "INVALID_DOT";
            case -3: return "LAYOUT_FAILED";
            case -4: return "RENDER_FAILED";
            case -5: return "INVALID_ENGINE";
            case -6: return "INVALID_FORMAT";
            case -7: return "OUT_OF_MEMORY";
            case -8: return "NOT_INITIALIZED";
            default: return "UNKNOWN";
        }
    }

    /*
     * JNI native methods.
     * These are implemented in the CMake-built native library that
     * wraps graphviz_api.h via JNI.
     */
    private static native long nativeContextNew();
    private static native void nativeContextFree(long ctx);
    private static native int nativeRender(long ctx, String dot, String engine,
                                            String format, String[] outResult);
    private static native String nativeStrerror(int err);
    private static native String nativeVersion();
}
