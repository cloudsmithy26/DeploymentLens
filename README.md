# DeploymentLens

Native Salesforce app that surfaces component-level detail for deployments:
a recent-deployments dashboard, deployment-Id search, and a drill-down showing
component successes/failures and Apex test results — directly in the org's UI.

Built as SFDX source, API v67.0. Internal API names use the
`Deployment_Overview` / `deploymentOverview` prefix for stability across
upgrades; all user-facing labels say DeploymentLens.

---

## 1. Installing into a target org

**Option A — install the package (recommended for orgs you don't develop in):**

Open the install URL you generated (see section 4) while logged into the
target org, or run:

```bash
sf package install -p 04tXXXXXXXXXXXXXXX -o TargetOrg -w 10
```

**Option B — deploy the source directly (dev/scratch/sandbox):**

```bash
sf project deploy start -d force-app -o TargetOrg
```

Then, in either case, assign the permission set to every user who should see
the app:

```bash
sf org assign permset -n Deployment_Overview_User -o TargetOrg
```

---

## 2. Configuring the target org (one-time, ~10 minutes)

The package ships the External Credential (`Deployment_Overview_Self_EC`,
OAuth Client Credentials Flow), the Named Credential
(`Deployment_Overview_Self`), and principal access via the permission set.
Salesforce never packages secrets or org URLs, so three steps remain.

**Open App Launcher → DeploymentLens Setup.** The Setup Assistant displays
the exact org-specific values referenced below with copy buttons, and has a
Test connection button — use it instead of typing URLs by hand.

### Step 1 — Create an External Client App

Setup → External Client App Manager → New:

- Enable OAuth. Callback URL: paste the value from the Setup tab (unused by
  this flow, but the field is required).
- OAuth scope: `api`.
- Under **Settings**, enable the **Client Credentials Flow**.
- Save, then copy the **consumer key** and **consumer secret**.

Now the step everyone misses — the Run-As user lives on a different tab:

- Open the app → **Policies** tab → Edit → OAuth Policies →
  **Client Credentials Flow**: enable it here too and set **Run As** to an
  admin user with API access. Save.

Wait 5–10 minutes: new OAuth apps propagate slowly, and authenticating
immediately throws `invalid_client_id` even when everything is correct.

### Step 2 — Point the External Credential at this org

Setup → Named Credentials → External Credentials tab → **DeploymentLens
Self EC** → Edit:

- Set the token endpoint (Identity Provider URL) to the value shown in the
  Setup tab: `https://<this-org-domain>/services/oauth2/token`
- Edit the **Admin** principal: paste the consumer key (Client Id) and
  consumer secret (Client Secret) from Step 1, and save.

### Step 3 — Point the Named Credential at this org

Setup → Named Credentials → **DeploymentLens Self** → Edit:

- Set URL to the org domain shown in the Setup tab
  (always `https://…my.salesforce.com` — see the table below).

### Step 4 — Test

Click **Test connection** in the Setup tab. Anything other than Success
comes with a diagnosis (see Troubleshooting).

### Org URL formats

Never copy the URL from the browser address bar (that gives the
`.lightning.force.com` UI domain, which redirects API calls and breaks the
Named Credential). Use the Setup tab's value or `sf org display`:

| Org type          | URL pattern                                  |
|-------------------|----------------------------------------------|
| Production        | `acme.my.salesforce.com`                     |
| Developer Edition | `acme-dev-ed.develop.my.salesforce.com`      |
| Scratch org       | `random-words-1234.scratch.my.salesforce.com`|
| Sandbox           | `acme--uat.sandbox.my.salesforce.com`        |

---

## 3. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `invalid_grant: no client credentials user enabled` | No Run-As user on the External Client App. Policies tab → OAuth Policies → Client Credentials Flow → set Run As. |
| `invalid_client_id` | OAuth app still propagating — wait 5–10 min and retry. |
| HTTP 302 / "Redirected to …" | Named Credential URL points at the wrong host (usually `.lightning.force.com`). Use the Setup tab's org URL. |
| HTTP 401 | Wrong consumer key/secret on the Admin principal, or Client Credentials Flow not enabled in the app's Settings. |
| HTTP 403 | Run-As user lacks API Enabled / deploy-visibility permissions. |
| "We couldn't access the credential(s)" | User's permission set lacks principal access (packaged — reassign `Deployment_Overview_User`), or the Admin principal was never saved with a secret. |
| Empty dashboard, no error | No deployments in the last ~30 days — the Tooling API `DeployRequest` object only retains recent history. Deploy anything and refresh. |

---

## 4. Creating the installable package (done once, from the Dev Hub)

```bash
sf package create --name "DeploymentLens" --package-type Unlocked --path force-app -v DevHub
sf package version create -p "DeploymentLens" -x --code-coverage -w 30 -v DevHub
sf package version promote -p "DeploymentLens@1.0.0-1" -v DevHub   # required for prod installs
```

`version create` outputs the `04t…` Id. Install URL for any org:
`https://login.salesforce.com/packaging/installPackage.apexp?p0=04t…`
(use `test.salesforce.com` for sandboxes).

---

## 5. Development

```bash
sf org login web --set-default-dev-hub --alias DevHub
sf org create scratch -f config/project-scratch-def.json -a lensDev -d 7 --set-default
sf project deploy start -d force-app
sf org assign permset -n Deployment_Overview_User
sf apex run test -w 10
sf org open
```

Architecture: `deploymentOverview` LWC (container, App Builder-configurable
row limit) → `deploymentList` / `deploymentDetail`; `setupAssistant` backs the
Setup tab. Apex `DeploymentOverviewController` queries the Tooling API
`DeployRequest` object for the list and
`GET /services/data/v67.0/metadata/deployRequest/{id}?includeDetails=true`
for the drill-down (payload key: `deployResult`), all through the Named
Credential — no session Ids, AppExchange-security-review friendly.

Known limits: `includeDetails=true` returns everything in one payload — very
large deployments (10k+ components) can approach the 6 MB Apex heap limit.
Tooling API history retention is ~30 days. Each refresh consumes an org API
call; avoid aggressive polling.

If the packaged External/Named Credential XML is rejected on deploy (schema
varies slightly by release), delete those two files and create both records
manually in Setup with the same API names — the Setup Assistant works either way.
