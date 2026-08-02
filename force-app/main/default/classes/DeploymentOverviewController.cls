/**
 * @description Server-side controller for the DeploymentLens app.
 * Retrieves deployment (DeployRequest) records via the Tooling API and full
 * component-level detail via the Metadata REST API, using a loopback callout
 * authenticated through a Named Credential (Deployment_Overview_Self).
 *
 * SECURITY NOTES (AppExchange review):
 *  - No session-ID usage: all callouts go through the Named Credential.
 *  - Access is gated by the Deployment_Overview_Access custom permission.
 *  - Deployment IDs are validated against a strict key-prefix pattern before use.
 */
public with sharing class DeploymentOverviewController {

    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:Deployment_Overview_Self';
    private static final String API_VERSION = 'v67.0';
    private static final Pattern DEPLOY_ID_PATTERN = Pattern.compile('^0Af[a-zA-Z0-9]{12,15}$');
    private static final Integer MAX_LIMIT = 50;
    private static final Integer DEFAULT_LIMIT = 10;

    /**
     * @description Returns the most recent deployments in the org.
     * @param limitSize number of rows to return (clamped to 1..50, default 10)
     */
    @AuraEnabled
    public static List<DeploymentSummary> getRecentDeployments(Integer limitSize) {
        enforceAccess();
        Integer safeLimit = (limitSize == null || limitSize < 1 || limitSize > MAX_LIMIT)
            ? DEFAULT_LIMIT : limitSize;

        String soql = 'SELECT Id, Status, CheckOnly, CreatedDate, StartDate, CompletedDate, '
            + 'CreatedBy.Name, NumberComponentsTotal, NumberComponentsDeployed, '
            + 'NumberComponentErrors, NumberTestsTotal, NumberTestsCompleted, NumberTestErrors '
            + 'FROM DeployRequest ORDER BY CreatedDate DESC LIMIT ' + safeLimit;

        HttpResponse res = doGet('/services/data/' + API_VERSION + '/tooling/query/?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8'));

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<DeploymentSummary> results = new List<DeploymentSummary>();
        for (Object rec : (List<Object>) body.get('records')) {
            results.add(DeploymentSummary.fromToolingRecord((Map<String, Object>) rec));
        }
        return results;
    }

    /**
     * @description Returns one deployment by Id (search-by-ID use case).
     */
    @AuraEnabled
    public static List<DeploymentSummary> findDeploymentById(String deploymentId) {
        enforceAccess();
        String cleanId = validateDeployId(deploymentId);
        String soql = 'SELECT Id, Status, CheckOnly, CreatedDate, StartDate, CompletedDate, '
            + 'CreatedBy.Name, NumberComponentsTotal, NumberComponentsDeployed, '
            + 'NumberComponentErrors, NumberTestsTotal, NumberTestsCompleted, NumberTestErrors '
            + 'FROM DeployRequest WHERE Id = \'' + cleanId + '\'';

        HttpResponse res = doGet('/services/data/' + API_VERSION + '/tooling/query/?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8'));

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<DeploymentSummary> results = new List<DeploymentSummary>();
        for (Object rec : (List<Object>) body.get('records')) {
            results.add(DeploymentSummary.fromToolingRecord((Map<String, Object>) rec));
        }
        return results;
    }

    /**
     * @description Returns full component + test detail for one deployment via
     * the Metadata REST API deployRequest resource.
     */
    @AuraEnabled
    public static DeploymentDetail getDeploymentDetails(String deploymentId) {
        enforceAccess();
        String cleanId = validateDeployId(deploymentId);

        HttpResponse res = doGet('/services/data/' + API_VERSION
            + '/metadata/deployRequest/' + cleanId + '?includeDetails=true');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        // NOTE: the API returns the payload under "deployResult" (not "deploymentResult").
        Map<String, Object> deployResult = (Map<String, Object>) body.get('deployResult');
        if (deployResult == null) {
            throw new AuraHandledException('Unexpected response shape from Metadata API.');
        }
        return DeploymentDetail.fromDeployResult(deployResult);
    }

    // ---------------------------------------------------------------- helpers

    @TestVisible
    private static Boolean bypassAccessCheck = false;

    private static void enforceAccess() {
        if (bypassAccessCheck) { return; }
        if (!FeatureManagement.checkPermission('Deployment_Overview_Access')) {
            throw new AuraHandledException(
                'You do not have permission to view deployment details. '
                + 'Ask your administrator for the DeploymentLens User permission set.');
        }
    }

    private static String validateDeployId(String deploymentId) {
        String cleanId = deploymentId == null ? '' : deploymentId.trim();
        if (!DEPLOY_ID_PATTERN.matcher(cleanId).matches()) {
            throw new AuraHandledException(
                'Invalid deployment Id. Expected an Id starting with "0Af".');
        }
        return cleanId;
    }

    private static HttpResponse doGet(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (System.CalloutException e) {
            throw new AuraHandledException('Callout failed: ' + e.getMessage()
                + '. Verify the Deployment_Overview_Self Named Credential is configured.');
        }
        if (res.getStatusCode() == 302) {
            throw new AuraHandledException('Redirected to ' + res.getHeader('Location')
                + ' — the Named Credential URL host is wrong. Open the DeploymentLens '
                + 'Setup tab for the correct value.');
        }
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('API returned HTTP ' + res.getStatusCode()
                + ': ' + res.getStatus());
        }
        return res;
    }
}
