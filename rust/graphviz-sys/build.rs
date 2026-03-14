use std::env;
use std::path::PathBuf;

fn main() {
    // Strategy 1: GRAPHVIZ_ANYWHERE_DIR / GRAPHVIZ_NATIVE_DIR environment variable.
    if let Some(dir) = ["GRAPHVIZ_ANYWHERE_DIR", "GRAPHVIZ_NATIVE_DIR"]
        .iter()
        .find_map(|name| env::var(name).ok())
    {
        let base = PathBuf::from(&dir);

        // Look for the library in common subdirectories
        for sub in &["lib", "lib64", "build", "."] {
            let lib_dir = base.join(sub);
            if lib_dir.exists() {
                println!("cargo:rustc-link-search=native={}", lib_dir.display());
            }
        }

        // Also add the include path so downstream crates can find the header
        for sub in &["include", "src", "."] {
            let inc_dir = base.join(sub);
            if inc_dir.exists() {
                println!("cargo:include={}", inc_dir.display());
            }
        }

        println!("cargo:rustc-link-lib=dylib=graphviz_api");
        println!("cargo:rerun-if-env-changed=GRAPHVIZ_ANYWHERE_DIR");
        println!("cargo:rerun-if-env-changed=GRAPHVIZ_NATIVE_DIR");
        return;
    }

    // Strategy 2: pkg-config
    for library in ["graphviz-anywhere", "graphviz-native"] {
        if pkg_config::probe_library(library).is_ok() {
            // pkg-config sets the necessary link flags automatically
            println!("cargo:rerun-if-env-changed=GRAPHVIZ_ANYWHERE_DIR");
            println!("cargo:rerun-if-env-changed=GRAPHVIZ_NATIVE_DIR");
            return;
        }
    }

    // Strategy 3: system default paths
    let search_paths: &[&str] = if cfg!(target_os = "macos") {
        &["/usr/local/lib", "/opt/homebrew/lib"]
    } else if cfg!(target_os = "windows") {
        &[]
    } else {
        // Linux / other Unix
        &["/usr/local/lib", "/usr/lib", "/usr/lib64"]
    };

    for path in search_paths {
        let p = PathBuf::from(path);
        if p.exists() {
            println!("cargo:rustc-link-search=native={}", p.display());
        }
    }

    println!("cargo:rustc-link-lib=dylib=graphviz_api");
    println!("cargo:rerun-if-env-changed=GRAPHVIZ_ANYWHERE_DIR");
    println!("cargo:rerun-if-env-changed=GRAPHVIZ_NATIVE_DIR");
}
