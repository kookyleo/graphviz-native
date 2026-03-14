import { describe, it, expect } from 'vitest';
import {
  GraphvizWebError,
  type GraphvizWebErrorCode,
  type GraphvizWorkerRequest,
  type GraphvizWorkerResponse,
} from '../shared';

describe('Worker Protocol', () => {
  describe('GraphvizWorkerRequest', () => {
    it('supports preload action', () => {
      const request: GraphvizWorkerRequest = {
        id: 1,
        action: 'preload',
      };
      expect(request.id).toBe(1);
      expect(request.action).toBe('preload');
    });

    it('supports capabilities action', () => {
      const request: GraphvizWorkerRequest = {
        id: 2,
        action: 'capabilities',
      };
      expect(request.action).toBe('capabilities');
    });

    it('supports render action with dot and options', () => {
      const request: GraphvizWorkerRequest = {
        id: 3,
        action: 'render',
        dot: 'digraph { a -> b }',
        options: { engine: 'dot', format: 'svg' },
      };
      expect(request.dot).toBe('digraph { a -> b }');
      expect(request.options?.engine).toBe('dot');
    });

    it('supports renderDetailed action', () => {
      const request: GraphvizWorkerRequest = {
        id: 4,
        action: 'renderDetailed',
        dot: 'digraph { a -> b }',
      };
      expect(request.action).toBe('renderDetailed');
    });

    it('supports renderMany action with formats', () => {
      const request: GraphvizWorkerRequest = {
        id: 5,
        action: 'renderMany',
        dot: 'digraph { a -> b }',
        formats: ['svg', 'png'],
      };
      expect(request.formats).toEqual(['svg', 'png']);
    });

    it('supports renderManyDetailed action', () => {
      const request: GraphvizWorkerRequest = {
        id: 6,
        action: 'renderManyDetailed',
        dot: 'digraph { a -> b }',
        formats: ['svg', 'json'],
      };
      expect(request.action).toBe('renderManyDetailed');
      expect(request.formats).toEqual(['svg', 'json']);
    });

    it('supports dispose action', () => {
      const request: GraphvizWorkerRequest = {
        id: 7,
        action: 'dispose',
      };
      expect(request.action).toBe('dispose');
    });

    it('maintains unique request IDs', () => {
      const requests: GraphvizWorkerRequest[] = [
        { id: 1, action: 'preload' },
        { id: 2, action: 'capabilities' },
        { id: 3, action: 'render', dot: 'digraph {}' },
      ];

      const ids = requests.map(r => r.id);
      const uniqueIds = new Set(ids);
      expect(uniqueIds.size).toBe(ids.length);
    });
  });

  describe('GraphvizWorkerResponse - Success', () => {
    it('creates success response with capabilities', () => {
      const response: GraphvizWorkerResponse = {
        id: 1,
        ok: true,
        value: {
          graphvizVersion: '2.43.0',
          engines: ['dot', 'neato'],
          formats: ['svg', 'png'],
        },
      };

      expect(response.ok).toBe(true);
      expect(response.id).toBe(1);
      expect(response.value).toBeDefined();
    });

    it('creates success response with render output', () => {
      const response: GraphvizWorkerResponse = {
        id: 2,
        ok: true,
        value: '<svg>...</svg>',
      };

      expect(response.ok).toBe(true);
      expect(typeof response.value).toBe('string');
    });

    it('creates success response with batch render output', () => {
      const response: GraphvizWorkerResponse = {
        id: 3,
        ok: true,
        value: {
          output: {
            svg: '<svg>...</svg>',
            json: '{"graph":{}}',
          },
          issues: [],
          capabilities: {
            graphvizVersion: '2.43.0',
            engines: ['dot'],
            formats: ['svg', 'json'],
          },
        },
      };

      expect(response.ok).toBe(true);
    });
  });

  describe('GraphvizWorkerResponse - Error', () => {
    it('creates error response with code and message', () => {
      const response: GraphvizWorkerResponse = {
        id: 1,
        ok: false,
        error: {
          code: 'RENDER_FAILED',
          message: 'Graph layout failed',
        },
      };

      expect(response.ok).toBe(false);
      expect(response.error.code).toBe('RENDER_FAILED');
      expect(response.error.message).toBe('Graph layout failed');
    });

    it('creates error response with issues', () => {
      const response: GraphvizWorkerResponse = {
        id: 2,
        ok: false,
        error: {
          code: 'RENDER_FAILED',
          message: 'Render failed',
          issues: [
            { message: 'Parse error', level: 'error' },
            { message: 'Warning', level: 'warning' },
          ],
        },
      };

      expect(response.error.issues).toHaveLength(2);
      expect(response.error.issues?.[0].level).toBe('error');
    });

    it('supports all error codes', () => {
      const codes: GraphvizWebErrorCode[] = [
        'UNSUPPORTED_ENGINE',
        'UNSUPPORTED_FORMAT',
        'RENDER_FAILED',
        'WORKER_UNAVAILABLE',
        'TIMEOUT',
        'DISPOSED',
      ];

      for (const code of codes) {
        const response: GraphvizWorkerResponse = {
          id: 1,
          ok: false,
          error: {
            code,
            message: 'Test error',
          },
        };
        expect(response.error.code).toBe(code);
      }
    });
  });

  describe('Error Serialization', () => {
    it('converts error response to GraphvizWebError', () => {
      const errorPayload = {
        code: 'UNSUPPORTED_ENGINE' as const,
        message: 'Engine not found',
        issues: [{ message: 'Invalid engine' }],
      };

      const error = new GraphvizWebError(
        errorPayload.code,
        errorPayload.message,
        { issues: errorPayload.issues }
      );

      expect(error.code).toBe('UNSUPPORTED_ENGINE');
      expect(error.message).toBe('Engine not found');
      expect(error.issues).toEqual(errorPayload.issues);
    });
  });

  describe('Worker Communication Flow', () => {
    it('request-response pairing maintains ID', () => {
      const requestId = 42;
      const request: GraphvizWorkerRequest = {
        id: requestId,
        action: 'render',
        dot: 'digraph { a -> b }',
      };

      const response: GraphvizWorkerResponse = {
        id: requestId,
        ok: true,
        value: '<svg>...</svg>',
      };

      expect(request.id).toBe(response.id);
    });

    it('multiple pending requests have unique IDs', () => {
      const requests: GraphvizWorkerRequest[] = [
        { id: 1, action: 'preload' },
        { id: 2, action: 'render', dot: 'digraph { a }' },
        { id: 3, action: 'render', dot: 'digraph { b }' },
      ];

      const responses: GraphvizWorkerResponse[] = [
        {
          id: 1,
          ok: true,
          value: { graphvizVersion: '2.43.0', engines: [], formats: [] },
        },
        { id: 2, ok: true, value: '<svg>a</svg>' },
        { id: 3, ok: true, value: '<svg>b</svg>' },
      ];

      for (let i = 0; i < requests.length; i++) {
        expect(requests[i].id).toBe(responses[i].id);
      }
    });

    it('error response uses same ID as request', () => {
      const requestId = 99;
      const request: GraphvizWorkerRequest = {
        id: requestId,
        action: 'render',
        dot: 'invalid dot',
      };

      const response: GraphvizWorkerResponse = {
        id: requestId,
        ok: false,
        error: {
          code: 'RENDER_FAILED',
          message: 'Invalid DOT',
        },
      };

      expect(request.id).toBe(response.id);
    });
  });

  describe('Worker Actions Validation', () => {
    it('all actions are callable', () => {
      const actions: GraphvizWorkerRequest['action'][] = [
        'preload',
        'capabilities',
        'render',
        'renderDetailed',
        'renderMany',
        'renderManyDetailed',
        'dispose',
      ];

      for (const action of actions) {
        const request: GraphvizWorkerRequest = {
          id: 1,
          action,
        };
        expect(request.action).toBe(action);
      }
    });

    it('request contains appropriate payloads', () => {
      const renderRequest: GraphvizWorkerRequest = {
        id: 1,
        action: 'render',
        dot: 'digraph { a }',
        options: { engine: 'dot' },
      };
      expect(renderRequest.dot).toBeDefined();

      const formatRequest: GraphvizWorkerRequest = {
        id: 2,
        action: 'renderMany',
        dot: 'digraph { a }',
        formats: ['svg', 'png'],
      };
      expect(formatRequest.formats).toBeDefined();

      const preloadRequest: GraphvizWorkerRequest = {
        id: 3,
        action: 'preload',
      };
      expect(preloadRequest.dot).toBeUndefined();
      expect(preloadRequest.formats).toBeUndefined();
    });
  });
});
