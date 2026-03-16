// WebAssembly module type definitions
// Actual implementation provided at runtime by Emscripten compilation

export interface VizInstance {
  ccall: (name: string, returnType: string, paramTypes: string[], params: any[]) => any;
  cwrap: (name: string, returnType: string, paramTypes: string[]) => (...args: any[]) => any;
  UTF8ToString: (ptr: number) => string;
  lengthBytesUTF8: (str: string) => number;
  allocate: (data: any, type: string, allocType: number) => number;
  ALLOC_NORMAL: number;
  _malloc: (size: number) => number;
  _free: (ptr: number) => void;
}

declare const VizModule: () => Promise<VizInstance>;
export default VizModule;
