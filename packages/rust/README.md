# graphviz-anywhere (Rust crate)

<!-- TODO (follow-up PR): migrate the Rust crate to consume the shared
     C++ CGraphviz wrapper introduced in `packages/web/src-cpp/main.cpp`.
     Plan: replace the current C-ABI bindgen against `capi/graphviz_api.h`
     with a `cxx` bridge over the CGraphviz class, so all language
     bindings share one Graphviz core. Tracked alongside the rearch
     landed in the `rearch/hpcc-js-aligned` branch. -->

Rust crate published as `graphviz-anywhere` on crates.io.

## Status

This crate currently builds against the legacy C-ABI wrapper
(`capi/graphviz_api.{h,c}`) and is **not affected** by the web Wasm
rearch landed in `rearch/hpcc-js-aligned`. A follow-up PR will switch
the FFI surface to the `CGraphviz` C++ class via the `cxx` crate so all
platforms share one Graphviz implementation.
