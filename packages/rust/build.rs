use std::env;
use std::path::{Path, PathBuf};

fn emit_search_path(dir: &Path, dynamic: bool) {
    println!("cargo:rustc-link-search=native={}", dir.display());

    if dynamic && !cfg!(target_os = "windows") {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    }
}

fn try_env_override() -> bool {
    let Some(dir) = ["GRAPHVIZ_ANYWHERE_DIR", "GRAPHVIZ_NATIVE_DIR"]
        .iter()
        .find_map(|name| env::var(name).ok())
    else {
        return false;
    };

    let base = PathBuf::from(dir);
    let mut found = false;

    for sub in ["lib", "lib64", "build", "."] {
        let lib_dir = base.join(sub);
        if lib_dir.exists() {
            emit_search_path(&lib_dir, true);
            found = true;
        }
    }

    if found {
        println!("cargo:rustc-link-lib=dylib=graphviz_api");
    }

    found
}

fn try_prebuilt(manifest_dir: &Path) -> bool {
    let target_dir = if cfg!(target_os = "macos") {
        manifest_dir.join("prebuilt/macos")
    } else if cfg!(target_os = "linux") {
        manifest_dir.join("prebuilt/linux")
    } else if cfg!(target_os = "windows") {
        manifest_dir.join("prebuilt/windows")
    } else {
        return false;
    };

    if !target_dir.exists() {
        return false;
    }

    let static_lib = if cfg!(target_os = "windows") {
        target_dir.join("graphviz_api.lib")
    } else {
        target_dir.join("libgraphviz_api.a")
    };

    if !static_lib.exists() {
        return false;
    }

    emit_search_path(&target_dir, false);
    println!("cargo:rustc-link-lib=static=graphviz_api");
    true
}

fn try_repo_output(manifest_dir: &Path) -> bool {
    let Some(repo_root) = manifest_dir.parent().and_then(Path::parent) else {
        return false;
    };
    let output_root = repo_root.join("output");

    let candidates = if cfg!(target_os = "macos") {
        vec![output_root.join("macos-universal/lib")]
    } else if cfg!(target_os = "linux") {
        vec![
            output_root.join("linux-x86_64/lib"),
            output_root.join("linux/lib"),
        ]
    } else if cfg!(target_os = "windows") {
        vec![
            output_root.join("windows-x86_64/lib"),
            output_root.join("windows-x86_64/bin"),
        ]
    } else {
        Vec::new()
    };

    for dir in candidates {
        if dir.exists() {
            emit_search_path(&dir, true);
            println!("cargo:rustc-link-lib=dylib=graphviz_api");
            return true;
        }
    }

    false
}

fn main() {
    let target_arch =
        env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| "unknown".to_string());

    println!("cargo:rerun-if-env-changed=GRAPHVIZ_ANYWHERE_DIR");
    println!("cargo:rerun-if-env-changed=GRAPHVIZ_NATIVE_DIR");
    println!("cargo:rerun-if-changed=prebuilt/");

    // On wasm32, the Rust crate delegates to a host-provided JavaScript
    // function — no native linking required.
    if target_arch == "wasm32" {
        return;
    }

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

    if try_env_override() || try_prebuilt(&manifest_dir) || try_repo_output(&manifest_dir) {
        return;
    }

    panic!(
        "Unable to locate graphviz_api. Set GRAPHVIZ_ANYWHERE_DIR/GRAPHVIZ_NATIVE_DIR, \
or provide prebuilt libraries under packages/rust/prebuilt."
    );
}
