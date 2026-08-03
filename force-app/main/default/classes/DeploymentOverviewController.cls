/**
 * @description Server-side controller for the DeploymentLens app.
 * Retrieves deployment (DeployRequest) records via the Tooling API and full
 * component-level detail via the Metadata REST API, using a loopback callout
 * authenticated through the Deployment_Overview_Self Named Credential.
 *
 * SECURITY NOTES (AppExchange review):
 *  - No session-Id usage: all callouts go through the Named Credential.
 *  - Access is gated by the Deployment_Overview_Access custom permission.
 *  - Deployment Ids are validated against a strict key-prefix pattern before use.
 */
public with sharing class DeploymentOverviewController {

    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:Deployment_Overview_Self';
    private static final String API_VERSION = 'v67.0';
    private static final Pattern DEPLOY_ID_PATTERN = Pattern.compile('^0Af[a-zA-Z0-9]{12,15}$');
    private static final Integer MAX_QUERY_LIMIT = 50;
    private static final Integer DEFAULT_QUERY_LIMIT = 10;
    private static final String DEPLOY_REQUEST_FIELDS =
        'SELECT Id, Status, CheckOnly, CreatedDate, StartDate, CompletedDate, '
        + 'CreatedBy.Name, NumberComponentsTotal, NumberComponentsDeployed, '
        + 'NumberComponentErrors, NumberTestsTotal, NumberTestsCompleted, NumberTestErrors '
        + 'FROM DeployRequest ';

    @TestVisible
    private static Boolean bypassAccessCheck = false;

    /**
     * @description Returns the most recent deployments in the org.
     * @param limitSize number of rows to return (clamped to 1..50, default 10)
     */
    @AuraEnabled
    public static List<DeploymentSummary> getRecentDeployments(Integer limitSize) {
        enforceAccess();
        Integer safeQueryLimit = (limitSize == null || limitSize < 1 || limitSize > MAX_QUERY_LIMIT)
            ? DEFAULT_QUERY_LIMIT : limitSize;
        String deployRequestQuery = DEPLOY_REQUEST_FIELDS
            + 'ORDER BY CreatedDate DESC LIMIT ' + safeQueryLimit;
        return queryDeployments(deployRequestQuery);
    }

    /**
     * @description Returns one deployment by Id (search-by-Id use case).
     */
    @AuraEnabled
    public static List<DeploymentSummary> findDeploymentById(String deploymentId) {
        enforceAccess();
        String validatedDeploymentId = validateDeploymentId(deploymentId);
        String deployRequestQuery = DEPLOY_REQUEST_FIELDS
            + 'WHERE Id = \'' + validatedDeploymentId + '\'';
        return queryDeployments(deployRequestQuery);
    }

    /**
     * @description Returns full component and test detail for one deployment via
     * the Metadata REST API deployRequest resource.
     */
    @AuraEnabled
    public static DeploymentDetail getDeploymentDetails(String deploymentId) {
        enforceAccess();
        String validatedDeploymentId = validateDeploymentId(deploymentId);

        HttpResponse deployDetailResponse = doGet('/services/data/' + API_VERSION
            + '/metadata/deployRequest/' + validatedDeploymentId + '?includeDetails=true');

        Map<String, Object> mapResponseBody =
            (Map<String, Object>) JSON.deserializeUntyped(deployDetailResponse.getBody());
        // NOTE: the API returns the payload under "deployResult" (not "deploymentResult").
        Map<String, Object> mapDeployResult = (Map<String, Object>) mapResponseBody.get('deployResult');
        if (mapDeployResult == null) {
            throw new AuraHandledException('Unexpected response shape from Metadata API.');
        }
        return DeploymentDetail.fromDeployResult(mapDeployResult);
    }

    // ---------------------------------------------------------------- helpers

    private static List<DeploymentSummary> queryDeployments(String deployRequestQuery) {
        HttpResponse toolingQueryResponse = doGet('/services/data/' + API_VERSION
            + '/tooling/query/?q=' + EncodingUtil.urlEncode(deployRequestQuery, 'UTF-8'));

        Map<String, Object> mapResponseBody =
            (Map<String, Object>) JSON.deserializeUntyped(toolingQueryResponse.getBody());
        List<DeploymentSummary> listDeploymentSummaries = new List<DeploymentSummary>();
        for (Object deployRecordItem : (List<Object>) mapResponseBody.get('records')) {
            listDeploymentSummaries.add(
                DeploymentSummary.fromToolingRecord((Map<String, Object>) deployRecordItem));
        }
        return listDeploymentSummaries;
    }

    private static void enforceAccess() {
        if (bypassAccessCheck) { return; }
        if (!FeatureManagement.checkPermission('Deployment_Overview_Access')) {
            throw new AuraHandledException(
                'You do not have permission to view deployment details. '
                + 'Ask your administrator for the DeploymentLens User permission set.');
        }
    }

    private static String validateDeploymentId(String deploymentId) {
        String trimmedDeploymentId = deploymentId == null ? '' : deploymentId.trim();
        if (!DEPLOY_ID_PATTERN.matcher(trimmedDeploymentId).matches()) {
            throw new AuraHandledException(
                'Invalid deployment Id. Expected an Id starting with "0Af".');
        }
        return trimmedDeploymentId;
    }

    private static HttpResponse doGet(String resourcePath) {
        HttpRequest calloutRequest = new HttpRequest();
        calloutRequest.setEndpoint(NAMED_CREDENTIAL + resourcePath);
        calloutRequest.setMethod('GET');
        calloutRequest.setHeader('Accept', 'application/json');
        calloutRequest.setTimeout(120000);

        HttpResponse calloutResponse;
        try {
            calloutResponse = new Http().send(calloutRequest);
        } catch (System.CalloutException calloutException) {
            throw new AuraHandledException('Callout failed: ' + calloutException.getMessage()
                + '. Verify the Deployment_Overview_Self Named Credential is configured.');
        }
        if (calloutResponse.getStatusCode() == 302) {
            throw new AuraHandledException('Redirected to ' + calloutResponse.getHeader('Location')
                + ' — the Named Credential URL host is wrong. Open the DeploymentLens '
                + 'Setup tab for the correct value.');
        }
        if (calloutResponse.getStatusCode() != 200) {
            throw new AuraHandledException('API returned HTTP ' + calloutResponse.getStatusCode()
                + ': ' + calloutResponse.getStatus());
        }
        return calloutResponse;
    }
}
