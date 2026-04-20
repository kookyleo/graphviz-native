import { describe, it, expect } from 'vitest';
import { Graphviz, createGraphviz, GraphvizWebError } from '../index';

// Mock Embind module that mimics dist/viz.js' shape.
function mockEmbindModule(
  impl: {
    layout?: (dot: string, format: string, engine: string) => string;
    version?: string;
    lastError?: string;
  } = {}
) {
  const { layout, version = '14.1.5', lastError = '' } = impl;

  let instances = 0;
  let deletes = 0;

  const module = {
    CGraphviz: Object.assign(
      class {
        layout(dot: string, format: string, engine: string): string {
          if (!layout) {
            return `<svg format="${format}" engine="${engine}">${dot}</svg>`;
          }
          return layout(dot, format, engine);
        }
        delete(): void {
          deletes++;
        }
      },
      {
        version: () => version,
        lastError: () => lastError,
      }
    ),
  };

  // Count `new` via a proxy so we can assert cleanup.
  const OriginalCtor = module.CGraphviz;
  (module as { CGraphviz: typeof OriginalCtor }).CGraphviz = new Proxy(
    OriginalCtor,
    {
      construct(target, args) {
        instances++;
        return Reflect.construct(target, args);
      },
    }
  );

  return {
    module: module as unknown as Parameters<typeof Graphviz.load>[0] extends infer _ ? any : never,
    stats: () => ({ instances, deletes }),
  };
}

describe('Graphviz.load()', () => {
  it('exposes version(), layout(), and dot()', async () => {
    const { module } = mockEmbindModule({ version: '14.1.5' });
    const gv = await Graphviz.load({ factory: async () => module });

    expect(gv.version()).toBe('14.1.5');
    expect(gv.dot('digraph {}')).toContain('<svg');
    expect(gv.layout('digraph {}', 'json', 'neato')).toContain('format="json"');
  });

  it('delete()s each CGraphviz instance after use', async () => {
    const { module, stats } = mockEmbindModule();
    const gv = await Graphviz.load({ factory: async () => module });

    gv.dot('digraph { a -> b }');
    gv.layout('digraph {}', 'svg', 'dot');

    const { instances, deletes } = stats();
    expect(instances).toBe(2);
    expect(deletes).toBe(2);
  });

  it('throws GraphvizWebError when layout returns empty output', async () => {
    const { module } = mockEmbindModule({
      layout: () => '',
      lastError: 'syntax error on line 1',
    });
    const gv = await Graphviz.load({ factory: async () => module });

    expect(() => gv.dot('not dot')).toThrow(GraphvizWebError);
  });

  it('throws GraphvizWebError when layout throws', async () => {
    const { module } = mockEmbindModule({
      layout: () => {
        throw new Error('wasm aborted');
      },
    });
    const gv = await Graphviz.load({ factory: async () => module });

    try {
      gv.dot('digraph {}');
      expect.fail('expected throw');
    } catch (error) {
      expect(error).toBeInstanceOf(GraphvizWebError);
      expect((error as GraphvizWebError).code).toBe('RENDER_FAILED');
      expect((error as Error).message).toContain('wasm aborted');
    }
  });

  it('createGraphviz() is an alias for Graphviz.load()', async () => {
    const { module } = mockEmbindModule();
    const gv = await createGraphviz({ factory: async () => module });
    expect(gv).toBeInstanceOf(Graphviz);
  });

  it('defaults format to svg and engine to dot', async () => {
    let captured = { format: '', engine: '' };
    const { module } = mockEmbindModule({
      layout: (_dot, format, engine) => {
        captured = { format, engine };
        return '<svg/>';
      },
    });
    const gv = await Graphviz.load({ factory: async () => module });

    gv.dot('digraph {}');
    expect(captured).toEqual({ format: 'svg', engine: 'dot' });

    gv.layout('digraph {}');
    expect(captured).toEqual({ format: 'svg', engine: 'dot' });
  });
});
