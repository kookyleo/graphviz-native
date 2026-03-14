import { type GraphvizBatchDiagnostics, type GraphvizCapabilities, type GraphvizRenderDiagnostics, type GraphvizRenderOptions, type LoadVizWasmModule } from './shared';
export * from './shared';
export interface GraphvizRenderer {
    preload(): Promise<GraphvizCapabilities>;
    getCapabilities(): Promise<GraphvizCapabilities>;
    render(dot: string, options?: GraphvizRenderOptions): Promise<string>;
    renderDetailed(dot: string, options?: GraphvizRenderOptions): Promise<GraphvizRenderDiagnostics>;
    renderMany(dot: string, formats: string[], options?: Omit<GraphvizRenderOptions, 'format'>): Promise<Record<string, string>>;
    renderManyDetailed(dot: string, formats: string[], options?: Omit<GraphvizRenderOptions, 'format'>): Promise<GraphvizBatchDiagnostics>;
    dispose(): Promise<void>;
}
export interface LazyWasmRendererOptions {
    loadModule?: LoadVizWasmModule;
    warmup?: boolean;
}
export interface ServerWasmRendererOptions {
    loadModule?: LoadVizWasmModule;
    eager?: boolean;
}
export interface WorkerWasmRendererOptions {
    worker?: Worker;
    workerFactory?: () => Worker;
    timeoutMs?: number;
    terminateOnDispose?: boolean;
}
export declare function createLazyWasmRenderer(options?: LazyWasmRendererOptions): GraphvizRenderer;
export declare function createServerWasmRenderer(options?: ServerWasmRendererOptions): GraphvizRenderer;
export declare function createDefaultGraphvizWorker(): Worker;
export declare function createWorkerWasmRenderer(options?: WorkerWasmRendererOptions): GraphvizRenderer;
