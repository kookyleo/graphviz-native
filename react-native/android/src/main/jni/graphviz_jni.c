/*
 * graphviz_jni.c
 *
 * JNI bridge between the Java GraphvizModule and the C graphviz_api.
 * Handles string conversions and memory management across the JNI boundary.
 *
 * Licensed under the Apache License, Version 2.0
 */

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#include "graphviz_api.h"

#define TAG "GraphvizJNI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* Base64 encoding table */
static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/**
 * Simple base64 encoder for binary output (png, pdf, ps).
 * Caller must free the returned string.
 */
static char *base64_encode(const char *data, size_t len, size_t *out_len) {
    size_t olen = 4 * ((len + 2) / 3);
    char *out = (char *)malloc(olen + 1);
    if (!out) return NULL;

    size_t i, j;
    for (i = 0, j = 0; i < len;) {
        uint32_t a = i < len ? (unsigned char)data[i++] : 0;
        uint32_t b = i < len ? (unsigned char)data[i++] : 0;
        uint32_t c = i < len ? (unsigned char)data[i++] : 0;
        uint32_t triple = (a << 16) | (b << 8) | c;

        out[j++] = b64_table[(triple >> 18) & 0x3F];
        out[j++] = b64_table[(triple >> 12) & 0x3F];
        out[j++] = b64_table[(triple >> 6) & 0x3F];
        out[j++] = b64_table[triple & 0x3F];
    }

    /* Padding */
    size_t mod = len % 3;
    if (mod == 1) {
        out[olen - 1] = '=';
        out[olen - 2] = '=';
    } else if (mod == 2) {
        out[olen - 1] = '=';
    }

    out[olen] = '\0';
    if (out_len) *out_len = olen;
    return out;
}

/**
 * Returns non-zero if the format produces text (not binary) output.
 */
static int is_text_format(const char *format) {
    return (strcmp(format, "svg") == 0 ||
            strcmp(format, "json") == 0 ||
            strcmp(format, "dot") == 0 ||
            strcmp(format, "xdot") == 0 ||
            strcmp(format, "plain") == 0);
}

JNIEXPORT jlong JNICALL
Java_com_graphviznative_GraphvizModule_nativeContextNew(JNIEnv *env, jclass clazz) {
    gv_context_t *ctx = gv_context_new();
    return (jlong)(intptr_t)ctx;
}

JNIEXPORT void JNICALL
Java_com_graphviznative_GraphvizModule_nativeContextFree(JNIEnv *env, jclass clazz, jlong ptr) {
    gv_context_t *ctx = (gv_context_t *)(intptr_t)ptr;
    if (ctx) {
        gv_context_free(ctx);
    }
}

JNIEXPORT jint JNICALL
Java_com_graphviznative_GraphvizModule_nativeRender(
    JNIEnv *env, jclass clazz,
    jlong ptr, jstring jDot, jstring jEngine, jstring jFormat,
    jobjectArray outResult
) {
    gv_context_t *ctx = (gv_context_t *)(intptr_t)ptr;

    const char *dot = (*env)->GetStringUTFChars(env, jDot, NULL);
    const char *engine = (*env)->GetStringUTFChars(env, jEngine, NULL);
    const char *format = (*env)->GetStringUTFChars(env, jFormat, NULL);

    if (!dot || !engine || !format) {
        if (dot) (*env)->ReleaseStringUTFChars(env, jDot, dot);
        if (engine) (*env)->ReleaseStringUTFChars(env, jEngine, engine);
        if (format) (*env)->ReleaseStringUTFChars(env, jFormat, format);
        return (jint)GV_ERR_NULL_INPUT;
    }

    char *outData = NULL;
    size_t outLength = 0;

    gv_error_t err = gv_render(ctx, dot, engine, format, &outData, &outLength);

    if (err == GV_OK && outData) {
        jstring result;
        if (is_text_format(format)) {
            result = (*env)->NewStringUTF(env, outData);
        } else {
            size_t b64Len = 0;
            char *b64 = base64_encode(outData, outLength, &b64Len);
            if (b64) {
                result = (*env)->NewStringUTF(env, b64);
                free(b64);
            } else {
                result = NULL;
                err = GV_ERR_OUT_OF_MEMORY;
            }
        }

        if (result) {
            (*env)->SetObjectArrayElement(env, outResult, 0, result);
        }
    }

    if (outData) {
        gv_free_render_data(outData);
    }

    (*env)->ReleaseStringUTFChars(env, jDot, dot);
    (*env)->ReleaseStringUTFChars(env, jEngine, engine);
    (*env)->ReleaseStringUTFChars(env, jFormat, format);

    return (jint)err;
}

JNIEXPORT jstring JNICALL
Java_com_graphviznative_GraphvizModule_nativeStrerror(JNIEnv *env, jclass clazz, jint err) {
    const char *msg = gv_strerror((gv_error_t)err);
    return (*env)->NewStringUTF(env, msg ? msg : "Unknown error");
}

JNIEXPORT jstring JNICALL
Java_com_graphviznative_GraphvizModule_nativeVersion(JNIEnv *env, jclass clazz) {
    const char *ver = gv_version();
    return (*env)->NewStringUTF(env, ver ? ver : "unknown");
}
