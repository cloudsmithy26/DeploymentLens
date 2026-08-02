/**
 * @description Backs the Setup Assistant tab: surfaces the org-specific values
 * the admin must paste during post-install setup, and runs a diagnosed
 * connection test against the packaged Named Credential.
 */
public with sharing class DeploymentOverviewSetupController {

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSetupInfo() {
        String orgUrl = Url.getOrgDomainUrl().toExternalForm();
        return new Map<String, String>{
            'orgUrl' => orgUrl,
            'tokenEndpoint' => orgUrl + '/services/oauth2/token',
            'callbackUrl' => orgUrl + '/services/authcallback/unused',
            'namedCredential' => 'Deployment_Overview_Self',
            'externalCredential' => 'Deployment_Overview_Self_EC'
        };
    }

    @AuraEnabled
    public static Map<String, String> testConnection() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Deployment_Overview_Self/services/data/v67.0/tooling/query/?q='
            + EncodingUtil.urlEncode('SELECT Id FROM DeployRequest LIMIT 1', 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (System.CalloutException e) {
            String msg = e.getMessage();
            if (msg.containsIgnoreCase('no client credentials user')) {
                return result('Failed', msg,
                    'The External Client App has no Run-As user for the Client Credentials '
                    + 'Flow. Open the app, go to the Policies tab, edit OAuth Policies, '
                    + 'enable the Client Credentials Flow there, and set a Run As user.');
            }
            String guidance = msg.containsIgnoreCase('credential')
                ? 'The External Credential principal is missing, has no client secret saved, '
                    + 'or your permission set lacks principal access. Open the External '
                    + 'Credential, edit the Admin principal, and re-save the consumer key/secret.'
                : 'Callout blocked before reaching Salesforce. Check the Named Credential exists and is named exactly Deployment_Overview_Self.';
            return result('Failed', msg, guidance);
        }

        Integer sc = res.getStatusCode();
        if (sc == 200) {
            return result('Success', 'HTTP 200', 'Connection works. The DeploymentLens tab is ready to use.');
        }
        if (sc == 302) {
            return result('Failed', 'HTTP 302 redirect to ' + res.getHeader('Location'),
                'The Named Credential URL points at the wrong host. Edit it to the exact org URL shown in step 1 (.my.salesforce.com — never .lightning.force.com).');
        }
        if (sc == 401) {
            return result('Failed', 'HTTP 401',
                'Authentication rejected. Verify the consumer key/secret on the External Credential principal, that the External Client App has the Client Credentials Flow enabled, and that a Run-As user is set on the app.');
        }
        if (sc == 403) {
            return result('Failed', 'HTTP 403',
                'Authenticated but not authorized. The Run-As user on the External Client App needs API Enabled and Modify Metadata (or similar deploy-visibility) permissions.');
        }
        return result('Failed', 'HTTP ' + sc + ' ' + res.getStatus(), 'Unexpected response. Check the token endpoint URL on the External Credential.');
    }

    private static Map<String, String> result(String status, String detail, String guidance) {
        return new Map<String, String>{ 'status' => status, 'detail' => detail, 'hint' => guidance };
    }
}
