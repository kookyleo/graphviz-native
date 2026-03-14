import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

/**
 * TurboModule spec for the Graphviz native module (New Architecture).
 *
 * This interface defines the contract between JS and native code.
 * For the old architecture, we fall back to NativeModules.
 */
export interface Spec extends TurboModule {
  /**
   * Render a DOT string to the specified format.
   *
   * @param dot - DOT language string
   * @param engine - Layout engine (dot, neato, fdp, sfdp, circo, twopi, osage, patchwork)
   * @param format - Output format (svg, png, pdf, ps, json, dot, xdot, plain)
   * @returns Rendered output as a string (base64 for binary formats)
   */
  renderDot(dot: string, engine: string, format: string): Promise<string>;

  /**
   * Get the Graphviz library version string.
   */
  getVersion(): Promise<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('GraphvizNative');
