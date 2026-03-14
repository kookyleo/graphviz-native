import { createServerWasmRenderer } from './index';
import { GraphvizWebError, } from './shared';
const scope = self;
const renderer = createServerWasmRenderer();
function serializeError(error) {
    if (error instanceof GraphvizWebError) {
        return {
            code: error.code,
            message: error.message,
            issues: error.issues,
        };
    }
    if (error instanceof Error) {
        return {
            code: 'RENDER_FAILED',
            message: error.message,
        };
    }
    return {
        code: 'RENDER_FAILED',
        message: 'Unknown Graphviz worker error.',
    };
}
scope.addEventListener('message', async (event) => {
    const request = event.data;
    if (!request || typeof request !== 'object') {
        return;
    }
    try {
        let value;
        switch (request.action) {
            case 'preload':
            case 'capabilities':
                value = await renderer.getCapabilities();
                break;
            case 'render':
                value = await renderer.render(request.dot ?? '', request.options);
                break;
            case 'renderDetailed':
                value = await renderer.renderDetailed(request.dot ?? '', request.options);
                break;
            case 'renderMany':
                value = await renderer.renderMany(request.dot ?? '', request.formats ?? [], request.options);
                break;
            case 'renderManyDetailed':
                value = await renderer.renderManyDetailed(request.dot ?? '', request.formats ?? [], request.options);
                break;
            case 'dispose':
                await renderer.dispose();
                value = undefined;
                break;
            default:
                throw new GraphvizWebError('RENDER_FAILED', `Unsupported worker action: ${request.action}`);
        }
        const response = {
            id: request.id,
            ok: true,
            value,
        };
        scope.postMessage(response);
        if (request.action === 'dispose') {
            scope.close();
        }
    }
    catch (error) {
        const response = {
            id: request.id,
            ok: false,
            error: serializeError(error),
        };
        scope.postMessage(response);
    }
});
