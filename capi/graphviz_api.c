/*
 * graphviz-anywhere C ABI wrapper implementation
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

/* Built-in list of supported layout engines */
static const char *gv_engines[] = {
    "dot", "neato", "fdp", "sfdp", "circo", "twopi", "osage", "patchwork", NULL
};

GV_API const char *gv_get_engines(void) {
    /* Return as JSON array string */
    return "["
           "\"dot\",\"neato\",\"fdp\",\"sfdp\","
           "\"circo\",\"twopi\",\"osage\",\"patchwork\""
           "]";
}

/* Built-in list of supported output formats */
GV_API const char *gv_get_formats(void) {
    /* Return as JSON array string */
    return "["
           "\"svg\",\"png\",\"pdf\",\"ps\","
           "\"json\",\"dot\",\"xdot\",\"plain\""
           "]";
}

/* Helper: simple JSON encoder for format results */
static char *encode_format_results(const char **formats, char **results,
                                    int count, size_t *out_len) {
    /* Estimate size for JSON object */
    size_t size = 256;
    for (int i = 0; i < count; i++) {
        size += strlen(formats[i]) + (results[i] ? strlen(results[i]) : 0) + 64;
    }

    char *json = (char *)malloc(size);
    if (!json) {
        return NULL;
    }

    /* Build JSON object: {"format1": "output1", ...} */
    strcpy(json, "{");
    int offset = 1;

    for (int i = 0; i < count; i++) {
        offset += sprintf(json + offset, "\"%s\":", formats[i]);

        if (results[i]) {
            /* Escape quotes in output (simple approach) */
            offset += sprintf(json + offset, "\"");
            const char *src = results[i];
            while (*src && offset < size - 100) {
                if (*src == '"' || *src == '\\') {
                    json[offset++] = '\\';
                }
                if (*src == '\n') {
                    json[offset++] = '\\';
                    json[offset++] = 'n';
                    src++;
                } else if (*src == '\r') {
                    json[offset++] = '\\';
                    json[offset++] = 'r';
                    src++;
                } else {
                    json[offset++] = *src++;
                }
            }
            offset += sprintf(json + offset, "\"");
        } else {
            offset += sprintf(json + offset, "null");
        }

        if (i < count - 1) {
            json[offset++] = ',';
        }
    }

    strcpy(json + offset, "}");
    *out_len = strlen(json);

    return json;
}

GV_API gv_error_t gv_render_formats(gv_context_t *ctx,
                                     const char *dot,
                                     const char *engine,
                                     const char *formats,
                                     char **out_data,
                                     size_t *out_length) {
    if (!ctx || !ctx->gvc) {
        return GV_ERR_NOT_INITIALIZED;
    }
    if (!dot || !engine || !formats || !out_data || !out_length) {
        return GV_ERR_NULL_INPUT;
    }

    *out_data = NULL;
    *out_length = 0;

    /* Parse DOT input (once) */
    Agraph_t *g = agmemread(dot);
    if (!g) {
        return GV_ERR_INVALID_DOT;
    }

    /* Apply layout (once) */
    int rc = gvLayout(ctx->gvc, g, engine);
    if (rc != 0) {
        agclose(g);
        return GV_ERR_LAYOUT_FAILED;
    }

    /* Parse formats JSON array: extract format names */
    const char *fmt_str = formats;
    char **fmt_list = (char **)malloc(32 * sizeof(char *));
    char **result_list = (char **)malloc(32 * sizeof(char *));
    int fmt_count = 0;

    if (fmt_list && result_list) {
        /* Simple JSON array parser for ["fmt1","fmt2",...] */
        while (*fmt_str && fmt_count < 32) {
            if (*fmt_str == '"') {
                const char *start = fmt_str + 1;
                const char *end = strchr(start, '"');
                if (end) {
                    int len = end - start;
                    fmt_list[fmt_count] = (char *)malloc(len + 1);
                    if (fmt_list[fmt_count]) {
                        strncpy(fmt_list[fmt_count], start, len);
                        fmt_list[fmt_count][len] = '\0';

                        /* Render to this format */
                        char *result = NULL;
                        unsigned int result_len = 0;
                        int render_rc = gvRenderData(ctx->gvc, g, fmt_list[fmt_count],
                                                     &result, &result_len);
                        result_list[fmt_count] = (render_rc == 0) ? result : NULL;
                        fmt_count++;
                    }
                    fmt_str = end + 1;
                    continue;
                }
            }
            fmt_str++;
        }
    }

    gvFreeLayout(ctx->gvc, g);
    agclose(g);

    /* Encode results as JSON and return */
    if (fmt_count > 0) {
        *out_data = encode_format_results((const char **)fmt_list,
                                          result_list, fmt_count, out_length);
    }

    /* Cleanup */
    for (int i = 0; i < fmt_count; i++) {
        if (fmt_list[i]) {
            free(fmt_list[i]);
        }
        if (result_list[i]) {
            gvFreeRenderData(result_list[i]);
        }
    }
    free(fmt_list);
    free(result_list);

    return (*out_data) ? GV_OK : GV_ERR_RENDER_FAILED;
}
