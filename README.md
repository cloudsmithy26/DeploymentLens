# DeploymentLens

See inside your Salesforce deployments — component-level successes, failures,
and Apex test results, natively in the org UI.

The native Deployment Status page tells you *that* a deployment ran.
DeploymentLens shows you *what* it did: every component, every test class,
every failure message, without leaving Salesforce.

- **Recent deployments dashboard** — status, deploy vs. validation, initiator,
  component progress, and test errors for the last 5/10/20 deployments.
- **Deployment Id search** — paste any `0Af…` Id to jump straight to it.
- **Component drill-down** — successes and failures in separate tabs with
  metadata type, API name, and failure messages, plus every Apex test method's
  pass/fail outcome, runtime, and stack trace.

---

## Step 1 — Install the package

Install into your org with one of the following URLs (log in first):

| Org type | Install URL |
|---|---|
| Production / Developer Edition | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000aXzxAAE |
| Sandbox | https://test.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000aXzxAAE |

After installing:

1. **Assign the permission set**: Setup → Permission Sets →
   **DeploymentLens User** → Manage Assignments → add your users.
2. **Open the Setup Assistant**: App Launcher → **DeploymentLens Setup**.
   It shows your org's exact configuration values with copy buttons and a
   Test connection button — keep it open for steps 2–4.

## Step 2 — Create an External Client App

Setup → **External Client App Manager** → **New**:

1. External Client App Name: **DeploymentLens**. Contact Email: your email.
2. Expand **API (Enable OAuth Settings)** and select the checkbox **Enable OAuth**.
3. **Callback URL**: copy the value from the DeploymentLens Setup screen
   (the field is required but unused by this flow).
4. **OAuth Scopes** → from Available OAuth Scopes, add
   **Manage user data via APIs (api)**.
5. **Flow Enablement** → select **Client Credentials Flow**.
6. Keep everything else default and click **Create**.

Then configure the policies (a separate tab — easy to miss):

7. Open the app → **Policies** tab → **Edit**.
8. Under **OAuth Flows and External Client App Enhancements**, select
   **Enable Client Credentials Flow** and set the **Run As** user to any
   admin user. Save.
9. Open **Consumer Key and Secret**, copy the consumer key (Client Id) and
   consumer secret (Client Secret), and keep them ready.

> New OAuth apps take 5–10 minutes to propagate. If step 5 below fails with
> `invalid_client_id`, wait and retry.

## Step 3 — Point the External Credential at this org

Setup → Named Credentials → **External Credentials** tab →
**DeploymentLens Self EC** → **Edit**:

1. Set the token endpoint (Identity Provider URL) to the value shown in the
   DeploymentLens Setup screen: `https://<your-org-domain>/services/oauth2/token`
2. Edit the **Admin** principal and paste the consumer key (Client Id) and
   consumer secret (Client Secret) from Step 2.

## Step 4 — Point the Named Credential at this org

Setup → Named Credentials → **DeploymentLens Self** → **Edit**:

1. Set **URL** to the org URL shown in the DeploymentLens Setup screen
   (always `https://…my.salesforce.com`).

> Never copy the URL from the browser address bar — that gives the
> `.lightning.force.com` UI domain, which redirects API calls and breaks the
> connection.

## Step 5 — Test

Click **Test connection** on the DeploymentLens Setup screen. On Success,
open the **DeploymentLens** tab — you're done. Any failure includes a
diagnosis; the table below has the full list.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `invalid_grant: no client credentials user enabled` | No Run-As user on the External Client App. Policies tab → OAuth Policies → Client Credentials Flow → set Run As (Step 2.8). |
| `invalid_client_id` | OAuth app still propagating — wait 5–10 minutes and retry. |
| HTTP 302 / "Redirected to …" | Named Credential URL points at the wrong host (usually `.lightning.force.com`). Use the Setup screen's org URL (Step 4). |
| HTTP 401 | Wrong consumer key/secret on the Admin principal, or Client Credentials Flow not enabled in the app's settings (Step 2.5). |
| HTTP 403 | Run-As user lacks API Enabled or deploy-visibility permissions. |
| "We couldn't access the credential(s)" | User is missing the DeploymentLens User permission set, or the Admin principal was never saved with a secret. |
| Empty dashboard, no error | No deployments in the last ~30 days — Salesforce only retains recent deployment history. Deploy anything and refresh. |

## Notes and limits

- Deployment history comes from the Salesforce Tooling API, which retains
  roughly 30 days — DeploymentLens is an operational view, not a permanent
  audit trail.
- Each refresh consumes one API call against your org's allocations.
- Very large deployments (10,000+ components) may exceed platform response
  limits on the drill-down view.

## Contributing

Development, scratch org, and packaging instructions are in
[DEVELOPMENT.md](DEVELOPMENT.md). Issues and pull requests welcome.
