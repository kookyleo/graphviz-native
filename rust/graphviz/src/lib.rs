//! Safe Rust wrapper for the graphviz-native C library.
//!
//! This crate provides a memory-safe, idiomatic Rust interface to Graphviz
//! layout and rendering. It wraps the low-level C ABI exposed by
//! `libgraphviz_api`.
//!
//! # Example
//!
//! ```no_run
//! use graphviz_native::{GraphvizContext, Engine, Format};
//!
//! let ctx = GraphvizContext::new().expect("failed to create context");
//! let dot = r#"digraph G { a -> b; }"#;
//! let svg = ctx.render(dot, Engine::Dot, Format::Svg).unwrap();
//! println!("{}", String::from_utf8_lossy(&svg));
//! ```
//!
//! # Thread Safety
//!
//! [`GraphvizContext`] is deliberately `!Send` and `!Sync` because the
//! underlying Graphviz library uses global mutable state and is not
//! thread-safe. Each thread that needs rendering should create its own context,
//! or access should be externally synchronized.

use std::ffi::{CStr, CString};
use std::marker::PhantomData;
use std::ptr;

use graphviz_native_sys as ffi;

/// Errors that can occur when using the Graphviz API.
#[derive(Debug, thiserror::Error)]
pub enum GraphvizError {
    /// The Graphviz context could not be allocated.
    #[error("failed to create graphviz context")]
    ContextCreationFailed,

    /// A null pointer was passed where a valid pointer was expected.
    #[error("null input provided to graphviz")]
    NullInput,

    /// The DOT source string is not valid.
    #[error("invalid DOT input")]
    InvalidDot,

    /// The layout engine failed to compute a layout.
    #[error("layout computation failed")]
    LayoutFailed,

    /// The rendering step failed.
    #[error("render failed")]
    RenderFailed,

    /// The requested layout engine name is not recognized.
    #[error("invalid layout engine")]
    InvalidEngine,

    /// The requested output format is not recognized.
    #[error("invalid output format")]
    InvalidFormat,

    /// Memory allocation failed inside the C library.
    #[error("out of memory")]
    OutOfMemory,

    /// The context has not been properly initialized.
    #[error("context not initialized")]
    NotInitialized,

    /// The DOT input string contains an interior NUL byte.
    #[error("DOT string contains interior NUL byte: {0}")]
    NulByteInInput(#[from] std::ffi::NulError),

    /// An unrecognized error code was returned by the C library.
    #[error("unknown graphviz error (code {0})")]
    Unknown(i32),
}

impl GraphvizError {
    /// Map a C error code to the corresponding Rust error variant.
    fn from_code(code: ffi::gv_error_t) -> Self {
        match code {
            ffi::GV_ERR_NULL_INPUT => Self::NullInput,
            ffi::GV_ERR_INVALID_DOT => Self::InvalidDot,
            ffi::GV_ERR_LAYOUT_FAILED => Self::LayoutFailed,
            ffi::GV_ERR_RENDER_FAILED => Self::RenderFailed,
            ffi::GV_ERR_INVALID_ENGINE => Self::InvalidEngine,
            ffi::GV_ERR_INVALID_FORMAT => Self::InvalidFormat,
            ffi::GV_ERR_OUT_OF_MEMORY => Self::OutOfMemory,
            ffi::GV_ERR_NOT_INITIALIZED => Self::NotInitialized,
            other => Self::Unknown(other),
        }
    }
}

/// Layout engine used to compute graph positions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Engine {
    /// Hierarchical layout for directed graphs (default).
    Dot,
    /// Spring-model layout via stress majorization.
    Neato,
    /// Force-directed placement.
    Fdp,
    /// Scalable force-directed placement for large graphs.
    Sfdp,
    /// Circular layout.
    Circo,
    /// Radial layout.
    Twopi,
    /// Clustered layout using a tree-map style.
    Osage,
    /// Squarified tree-map layout.
    Patchwork,
}

impl Engine {
    /// Return the C string name expected by the library.
    fn as_cstr(&self) -> &'static CStr {
        // SAFETY: all byte literals are valid NUL-terminated UTF-8.
        match self {
            Self::Dot => unsafe { CStr::from_bytes_with_nul_unchecked(b"dot\0") },
            Self::Neato => unsafe { CStr::from_bytes_with_nul_unchecked(b"neato\0") },
            Self::Fdp => unsafe { CStr::from_bytes_with_nul_unchecked(b"fdp\0") },
            Self::Sfdp => unsafe { CStr::from_bytes_with_nul_unchecked(b"sfdp\0") },
            Self::Circo => unsafe { CStr::from_bytes_with_nul_unchecked(b"circo\0") },
            Self::Twopi => unsafe { CStr::from_bytes_with_nul_unchecked(b"twopi\0") },
            Self::Osage => unsafe { CStr::from_bytes_with_nul_unchecked(b"osage\0") },
            Self::Patchwork => unsafe { CStr::from_bytes_with_nul_unchecked(b"patchwork\0") },
        }
    }
}

/// Output format for the rendered graph.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Format {
    /// Scalable Vector Graphics.
    Svg,
    /// Portable Network Graphics (raster).
    Png,
    /// Adobe Portable Document Format.
    Pdf,
    /// PostScript.
    Ps,
    /// JSON representation of the graph structure.
    Json,
    /// Canonical DOT output (re-serialized).
    DotOutput,
    /// Extended DOT with layout information.
    Xdot,
    /// Simple plain-text coordinate output.
    Plain,
}

impl Format {
    /// Return the C string name expected by the library.
    fn as_cstr(&self) -> &'static CStr {
        // SAFETY: all byte literals are valid NUL-terminated UTF-8.
        match self {
            Self::Svg => unsafe { CStr::from_bytes_with_nul_unchecked(b"svg\0") },
            Self::Png => unsafe { CStr::from_bytes_with_nul_unchecked(b"png\0") },
            Self::Pdf => unsafe { CStr::from_bytes_with_nul_unchecked(b"pdf\0") },
            Self::Ps => unsafe { CStr::from_bytes_with_nul_unchecked(b"ps\0") },
            Self::Json => unsafe { CStr::from_bytes_with_nul_unchecked(b"json\0") },
            Self::DotOutput => unsafe { CStr::from_bytes_with_nul_unchecked(b"dot\0") },
            Self::Xdot => unsafe { CStr::from_bytes_with_nul_unchecked(b"xdot\0") },
            Self::Plain => unsafe { CStr::from_bytes_with_nul_unchecked(b"plain\0") },
        }
    }
}

/// A Graphviz rendering context.
///
/// Wraps the opaque `gv_context_t` pointer from the C library.
/// Automatically frees the underlying resources when dropped.
///
/// This type is `!Send` and `!Sync` because Graphviz uses global mutable
/// state internally.
pub struct GraphvizContext {
    raw: *mut ffi::gv_context_t,
    /// Prevent Send and Sync: the raw pointer plus PhantomData<*mut ()>
    /// ensures the compiler treats this as neither Send nor Sync.
    _not_send_sync: PhantomData<*mut ()>,
}

impl GraphvizContext {
    /// Create a new Graphviz context.
    ///
    /// Returns an error if the underlying C library fails to allocate.
    pub fn new() -> Result<Self, GraphvizError> {
        let raw = unsafe { ffi::gv_context_new() };
        if raw.is_null() {
            return Err(GraphvizError::ContextCreationFailed);
        }
        Ok(Self {
            raw,
            _not_send_sync: PhantomData,
        })
    }

    /// Render a DOT language string into the requested output format.
    ///
    /// # Arguments
    ///
    /// * `dot` - A valid DOT language graph description.
    /// * `engine` - The layout algorithm to use.
    /// * `format` - The desired output format.
    ///
    /// # Returns
    ///
    /// The raw rendered bytes on success, or a [`GraphvizError`] on failure.
    /// For text formats like SVG, the bytes are valid UTF-8 and can be
    /// converted with `String::from_utf8`.
    pub fn render(
        &self,
        dot: &str,
        engine: Engine,
        format: Format,
    ) -> Result<Vec<u8>, GraphvizError> {
        let c_dot = CString::new(dot)?;
        let c_engine = engine.as_cstr();
        let c_format = format.as_cstr();

        let mut out_data: *mut std::os::raw::c_char = ptr::null_mut();
        let mut out_len: usize = 0;

        let rc = unsafe {
            ffi::gv_render(
                self.raw,
                c_dot.as_ptr(),
                c_engine.as_ptr(),
                c_format.as_ptr(),
                &mut out_data,
                &mut out_len,
            )
        };

        if rc != ffi::GV_OK {
            return Err(GraphvizError::from_code(rc));
        }

        // Copy the data into a Rust-owned Vec before freeing the C buffer.
        let bytes = if out_data.is_null() || out_len == 0 {
            Vec::new()
        } else {
            // SAFETY: gv_render guarantees out_data points to out_len valid bytes on success.
            let slice = unsafe { std::slice::from_raw_parts(out_data as *const u8, out_len) };
            slice.to_vec()
        };

        // Always free the C-allocated buffer.
        if !out_data.is_null() {
            unsafe { ffi::gv_free_render_data(out_data) };
        }

        Ok(bytes)
    }

    /// Render a DOT string and return the result as a UTF-8 string.
    ///
    /// This is a convenience wrapper around [`render`](Self::render) for
    /// text-based output formats (SVG, DOT, JSON, Plain, etc.).
    pub fn render_to_string(
        &self,
        dot: &str,
        engine: Engine,
        format: Format,
    ) -> Result<String, GraphvizError> {
        let bytes = self.render(dot, engine, format)?;
        // Graphviz text output is always valid UTF-8 in practice,
        // but we use lossy conversion for robustness.
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }
}

impl Drop for GraphvizContext {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { ffi::gv_context_free(self.raw) };
        }
    }
}

/// Return the Graphviz library version string.
///
/// Returns `None` if the C library returns a null pointer.
pub fn version() -> Option<String> {
    let ptr = unsafe { ffi::gv_version() };
    if ptr.is_null() {
        return None;
    }
    let cstr = unsafe { CStr::from_ptr(ptr) };
    Some(cstr.to_string_lossy().into_owned())
}

/// Return a human-readable description of a raw C error code.
///
/// Primarily useful for debugging; prefer the [`GraphvizError`] Display impl
/// in most cases.
pub fn strerror(code: i32) -> Option<String> {
    let ptr = unsafe { ffi::gv_strerror(code) };
    if ptr.is_null() {
        return None;
    }
    let cstr = unsafe { CStr::from_ptr(ptr) };
    Some(cstr.to_string_lossy().into_owned())
}

// GraphvizContext is intentionally !Send and !Sync via PhantomData<*mut ()>.
// Graphviz uses global mutable state and is not safe to share across threads.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_cstr_no_panic() {
        // Ensure all variants produce valid C strings.
        let engines = [
            Engine::Dot,
            Engine::Neato,
            Engine::Fdp,
            Engine::Sfdp,
            Engine::Circo,
            Engine::Twopi,
            Engine::Osage,
            Engine::Patchwork,
        ];
        for e in &engines {
            let s = e.as_cstr();
            assert!(!s.to_bytes().is_empty());
        }
    }

    #[test]
    fn format_cstr_no_panic() {
        let formats = [
            Format::Svg,
            Format::Png,
            Format::Pdf,
            Format::Ps,
            Format::Json,
            Format::DotOutput,
            Format::Xdot,
            Format::Plain,
        ];
        for f in &formats {
            let s = f.as_cstr();
            assert!(!s.to_bytes().is_empty());
        }
    }

    #[test]
    fn error_display() {
        let err = GraphvizError::InvalidDot;
        let msg = format!("{err}");
        assert!(msg.contains("invalid DOT"), "got: {msg}");
    }

    #[test]
    fn error_from_code_roundtrip() {
        let err = GraphvizError::from_code(ffi::GV_ERR_OUT_OF_MEMORY);
        assert!(matches!(err, GraphvizError::OutOfMemory));
    }

    #[test]
    fn nul_byte_in_input_is_error() {
        let result = CString::new("hello\0world");
        assert!(result.is_err());
    }
}
