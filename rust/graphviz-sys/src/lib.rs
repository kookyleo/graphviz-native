//! Raw FFI bindings to the graphviz-native C ABI wrapper.
//!
//! This crate provides low-level, unsafe bindings to `libgraphviz_api`.
//! Most users should prefer the safe `graphviz-native` wrapper crate instead.

#![allow(non_camel_case_types)]

use std::os::raw::c_char;

/// Error codes returned by the C API.
pub const GV_OK: i32 = 0;
pub const GV_ERR_NULL_INPUT: i32 = -1;
pub const GV_ERR_INVALID_DOT: i32 = -2;
pub const GV_ERR_LAYOUT_FAILED: i32 = -3;
pub const GV_ERR_RENDER_FAILED: i32 = -4;
pub const GV_ERR_INVALID_ENGINE: i32 = -5;
pub const GV_ERR_INVALID_FORMAT: i32 = -6;
pub const GV_ERR_OUT_OF_MEMORY: i32 = -7;
pub const GV_ERR_NOT_INITIALIZED: i32 = -8;

/// Error code type alias matching `gv_error_t` in the C header.
pub type gv_error_t = i32;

/// Opaque context handle. Must not be used across threads.
#[repr(C)]
pub struct gv_context_t {
    _opaque: [u8; 0],
}

extern "C" {
    /// Create a new Graphviz context. Returns null on failure.
    pub fn gv_context_new() -> *mut gv_context_t;

    /// Free a Graphviz context and all associated resources.
    pub fn gv_context_free(ctx: *mut gv_context_t);

    /// Render a DOT string to the specified format using the given layout engine.
    ///
    /// On success, `out_data` and `out_length` receive the rendered output.
    /// The caller must free `out_data` with [`gv_free_render_data`].
    pub fn gv_render(
        ctx: *mut gv_context_t,
        dot: *const c_char,
        engine: *const c_char,
        format: *const c_char,
        out_data: *mut *mut c_char,
        out_length: *mut usize,
    ) -> gv_error_t;

    /// Free render output data returned by [`gv_render`].
    pub fn gv_free_render_data(data: *mut c_char);

    /// Get a human-readable description of an error code.
    pub fn gv_strerror(err: gv_error_t) -> *const c_char;

    /// Get the Graphviz library version string.
    pub fn gv_version() -> *const c_char;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_codes_are_correct() {
        assert_eq!(GV_OK, 0);
        assert!(GV_ERR_NULL_INPUT < 0);
        assert!(GV_ERR_OUT_OF_MEMORY < 0);
    }
}
