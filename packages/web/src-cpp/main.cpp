// graphviz-anywhere — Emscripten Embind wrapper around libgraphviz
//
// Architecture adapted from hpcc-systems/hpcc-js-wasm/packages/graphviz
// (see https://github.com/hpcc-systems/hpcc-js-wasm). The key idea is to
// expose Graphviz through a typed C++ class via Embind so all calls go
// through typed method dispatch. This avoids routing user-facing calls
// through the wasm function-pointer table, which is where Graphviz's
// remaining K&R-style function-pointer casts historically caused V8 to
// reject the module at WebAssembly.compile().
//
// Licensed under the Apache License, Version 2.0 (matches the parent
// repository). The CGraphviz layout is MIT-licensed by hpcc-systems.

#include <cstddef>
#include <string>

#include <gvc.h>
#include <gvplugin.h>
#include <graphviz_version.h>

#include <emscripten.h>
#include <emscripten/bind.h>

extern gvplugin_library_t gvplugin_dot_layout_LTX_library;
extern gvplugin_library_t gvplugin_neato_layout_LTX_library;
extern gvplugin_library_t gvplugin_core_LTX_library;

lt_symlist_t lt_preloaded_symbols[] = {
    {"gvplugin_dot_layout_LTX_library", &gvplugin_dot_layout_LTX_library},
    {"gvplugin_neato_layout_LTX_library", &gvplugin_neato_layout_LTX_library},
    {"gvplugin_core_LTX_library", &gvplugin_core_LTX_library},
    {nullptr, nullptr}};

namespace {
std::string lastErrorStr;

int vizErrorf(char *buf) {
  if (buf) {
    lastErrorStr += buf;
  }
  return 0;
}
}  // namespace

extern int Y_invert;
static const int origYInvert = Y_invert;
extern int Nop;
static const int origNop = Nop;

class CGraphviz {
 public:
  static std::string version() { return PACKAGE_VERSION; }

  static std::string lastError() { return lastErrorStr; }

  CGraphviz(int yInvert = 0, int nop = 0) {
    Y_invert = yInvert > 0 ? yInvert : origYInvert;
    Nop = nop > 0 ? nop : origNop;

    lastErrorStr.clear();
    agseterr(AGERR);
    agseterrf(vizErrorf);
  }

  ~CGraphviz() = default;

  std::string layout_result;
  std::string layout(const std::string &src,
                     const std::string &format,
                     const std::string &engine) {
    layout_result.clear();
    lastErrorStr.clear();

    GVC_t *gvc = gvContextPlugins(lt_preloaded_symbols, true);
    if (!gvc) {
      lastErrorStr += "gvContextPlugins returned NULL";
      return layout_result;
    }

    Agraph_t *graph = agmemread(src.c_str());
    if (graph) {
      char *data = nullptr;
      std::size_t length = 0;

      if (gvLayout(gvc, graph, engine.c_str()) == 0) {
        if (gvRenderData(gvc, graph, format.c_str(), &data, &length) == 0 &&
            data != nullptr) {
          layout_result.assign(data, length);
        }
        gvFreeRenderData(data);
        gvFreeLayout(gvc, graph);
      }
      agclose(graph);
    }

    gvFinalize(gvc);
    gvFreeContext(gvc);

    return layout_result;
  }
};

EMSCRIPTEN_BINDINGS(graphvizlib_bindings) {
  using namespace emscripten;

  class_<CGraphviz>("CGraphviz")
      .constructor<>()
      .constructor<int, int>()
      .class_function("version", &CGraphviz::version)
      .class_function("lastError", &CGraphviz::lastError)
      .function("layout", &CGraphviz::layout);
}
