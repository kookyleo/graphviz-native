// Stub WebAssembly module for build-time type checking
// The actual Emscripten-compiled module is loaded at runtime

export default async function VizModule() {
  throw new Error('Wasm module not available in build environment. Make sure to build the Wasm target: npm run build:wasm');
}
