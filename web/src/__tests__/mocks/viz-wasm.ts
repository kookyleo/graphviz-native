import {
  type VizWasmInstance,
  type VizWasmModule,
  type VizSingleRenderResult,
  type VizBatchRenderResult,
  type GraphvizRenderOptions,
} from '../../shared';

export function createMockVizWasmInstance(options: {
  graphvizVersion?: string;
  engines?: string[];
  formats?: string[];
  renderSuccess?: boolean;
  renderError?: string;
} = {}): VizWasmInstance {
  const {
    graphvizVersion = '2.43.0',
    engines = ['dot', 'neato', 'fdp'],
    formats = ['svg', 'png', 'pdf', 'json', 'dot'],
    renderSuccess = true,
    renderError,
  } = options;

  return {
    graphvizVersion,
    engines,
    formats,

    render(input: string, options?: GraphvizRenderOptions): VizSingleRenderResult {
      if (!renderSuccess) {
        return {
          status: 'failure',
          errors: [
            {
              level: 'error',
              message: renderError || 'Render failed',
            },
          ],
        };
      }

      // Mock successful render
      const format = options?.format || 'svg';
      let mockOutput = '';

      if (format === 'svg') {
        mockOutput = '<svg>Mock SVG Output</svg>';
      } else if (format === 'json') {
        mockOutput = '{"name":"graph"}';
      } else if (format === 'dot') {
        mockOutput = input;
      } else if (format === 'plain') {
        mockOutput = 'graph 1.0 1.0 1.0\nnode a 0.5 0.5 0.1 0.1\n';
      } else {
        mockOutput = `Mock ${format} output`;
      }

      return {
        status: 'success',
        output: mockOutput,
        errors: [],
      };
    },

    renderFormats(
      input: string,
      formats: string[],
      options?: GraphvizRenderOptions
    ): VizBatchRenderResult {
      if (!renderSuccess) {
        return {
          status: 'failure',
          errors: [
            {
              level: 'error',
              message: renderError || 'Batch render failed',
            },
          ],
        };
      }

      const output: Record<string, string> = {};

      for (const format of formats) {
        if (format === 'svg') {
          output[format] = '<svg>Mock SVG</svg>';
        } else if (format === 'json') {
          output[format] = '{"name":"graph"}';
        } else if (format === 'dot') {
          output[format] = input;
        } else {
          output[format] = `Mock ${format} output`;
        }
      }

      return {
        status: 'success',
        output,
        errors: [],
      };
    },
  };
}

export function createMockVizWasmModule(options?: Parameters<typeof createMockVizWasmInstance>[0]): VizWasmModule {
  return {
    instance: async () => createMockVizWasmInstance(options),
  };
}
