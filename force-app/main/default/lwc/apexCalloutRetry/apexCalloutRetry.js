// The DeploymentLens self-callout authenticates through a Named Credential whose
// OAuth token is cached at the platform level and only refreshed on its own
// internal schedule — not when the target API rejects it with a 401. Retrying
// inside the same transaction therefore always replays the same stale token.
// Waiting a few seconds and retrying as a brand-new transaction gives the
// platform's refresh cycle a real chance to have replaced it by then.
const RETRY_DELAYS_MS = [1500, 4000];

function isRetryableAuthError(error) {
    const message = (error && error.body && error.body.message) || '';
    return message.includes('401') || message.includes('INVALID_SESSION_ID');
}

function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function callApexWithRetry(apexFunction, params) {
    for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
        try {
            return await apexFunction(params);
        } catch (error) {
            const isLastAttempt = attempt === RETRY_DELAYS_MS.length;
            if (isLastAttempt || !isRetryableAuthError(error)) {
                throw error;
            }
            await delay(RETRY_DELAYS_MS[attempt]);
        }
    }
    return undefined;
}
