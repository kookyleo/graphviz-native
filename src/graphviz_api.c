/*
 * graphviz-native C ABI wrapper implementation
 *
 * Licensed under the Apache License, Version 2.0
 */

#define GRAPHVIZ_API_EXPORTS

#include "graphviz_api.h"
#include <gvc.h>
#include <gvplugin.h>
#include <cgraph.h>
#include <stdlib.h>
#include <string.h>

/* Builtin plugin libraries - linked statically to avoid runtime plugin loading */
extern gvplugin_library_t gvplugin_dot_layout_LTX_library;
extern gvplugin_library_t gvplugin_neato_layout_LTX_library;
extern gvplugin_library_t gvplugin_core_LTX_library;

static lt_symlist_t gv_builtin_plugins[] = {
    { "gvplugin_dot_layout_LTX_library",   (void *)(&gvplugin_dot_layout_LTX_library) },
    { "gvplugin_neato_layout_LTX_library", (void *)(&gvplugin_neato_layout_LTX_library) },
    { "gvplugin_core_LTX_library",         (void *)(&gvplugin_core_LTX_library) },
    { 0, 0 }
};

struct gv_context {
    GVC_t *gvc;
};

GV_API gv_context_t *gv_context_new(void) {
    gv_context_t *ctx = (gv_context_t *)calloc(1, sizeof(gv_context_t));
    if (!ctx) {
        return NULL;
    }

    /* Use builtin plugins, disable demand loading */
    ctx->gvc = gvContextPlugins(gv_builtin_plugins, 0);
    if (!ctx->gvc) {
        free(ctx);
        return NULL;
    }

    return ctx;
}

GV_API void gv_context_free(gv_context_t *ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->gvc) {
        gvFinalize(ctx->gvc);
        gvFreeContext(ctx->gvc);
    }
    free(ctx);
}

GV_API gv_error_t gv_render(gv_context_t *ctx,
                             const char *dot,
                             const char *engine,
                             const char *format,
                             char **out_data,
                             size_t *out_length) {
    if (!ctx || !ctx->gvc) {
        return GV_ERR_NOT_INITIALIZED;
    }
    if (!dot || !engine || !format || !out_data || !out_length) {
        return GV_ERR_NULL_INPUT;
    }

    *out_data = NULL;
    *out_length = 0;

    /* Parse DOT input */
    Agraph_t *g = agmemread(dot);
    if (!g) {
        return GV_ERR_INVALID_DOT;
    }

    /* Apply layout */
    int rc = gvLayout(ctx->gvc, g, engine);
    if (rc != 0) {
        agclose(g);
        return GV_ERR_LAYOUT_FAILED;
    }

    /* Render to memory buffer */
    char *result = NULL;
    unsigned int length = 0;
    rc = gvRenderData(ctx->gvc, g, format, &result, &length);
    if (rc != 0) {
        gvFreeLayout(ctx->gvc, g);
        agclose(g);
        return GV_ERR_RENDER_FAILED;
    }

    *out_data = result;
    *out_length = (size_t)length;

    /* Cleanup graph and layout, but not the render data */
    gvFreeLayout(ctx->gvc, g);
    agclose(g);

    return GV_OK;
}

GV_API void gv_free_render_data(char *data) {
    gvFreeRenderData(data);
}

GV_API const char *gv_strerror(gv_error_t err) {
    switch (err) {
        case GV_OK:                return "success";
        case GV_ERR_NULL_INPUT:    return "null input parameter";
        case GV_ERR_INVALID_DOT:   return "invalid DOT input";
        case GV_ERR_LAYOUT_FAILED: return "layout computation failed";
        case GV_ERR_RENDER_FAILED: return "render failed";
        case GV_ERR_INVALID_ENGINE: return "invalid layout engine";
        case GV_ERR_INVALID_FORMAT: return "invalid output format";
        case GV_ERR_OUT_OF_MEMORY: return "out of memory";
        case GV_ERR_NOT_INITIALIZED: return "context not initialized";
        default:                   return "unknown error";
    }
}

GV_API const char *gv_version(void) {
    return PACKAGE_VERSION;
}
