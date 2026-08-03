# DeploymentLens — development guide

SFDX source, API v67.0. Internal API names use the `Deployment_Overview` /
`deploymentOverview` prefix for upgrade stability; user-facing labels say
DeploymentLens.

## Scratch org workflow

```bash
sf org login web --set-default-dev-hub --alias DevHub
sf org create scratch -f config/project-scratch-def.json -a lensDev -d 7 --set-default
sf project deploy start -d force-app
sf org assign permset -n Deployment_Overview_User
sf apex run test -w 10
sf org open
```

Note: a Developer Edition Dev Hub allows 3 active scratch orgs and ~6 creates
per day. After deploying, complete the credential setup via the DeploymentLens
Setup tab (see README steps 2–4) — the app shows no data until then, and a
fresh scratch org has no deployment history until you deploy something.

## Architecture

- LWC `deploymentOverview` (container; row limit configurable in App Builder)
  → `deploymentList` / `deploymentDetail`; `setupAssistant` backs the Setup tab.
- Apex `DeploymentOverviewController`: recent list via Tooling API
  `DeployRequest` query; drill-down via
  `GET /services/data/v67.0/metadata/deployRequest/{id}?includeDetails=true`
  (payload key: `deployResult`). All callouts go through the
  `Deployment_Overview_Self` Named Credential — no session Ids
  (AppExchange security review requirement).
- Access gated by the `Deployment_Overview_Access` custom permission.

## Coding guidelines

- No single-letter variable names; all names must be meaningful.
- Collections carry a type prefix: `listDeployments`, `setComponentNames`,
  `mapResponseBody`.
- `with sharing` on every class; validate all user input before use;
  errors surface as `AuraHandledException`.

## Packaging
- Update <DevHub Org Name> with your DevHub Org

```bash
sf package create --name "DeploymentLens" --package-type Unlocked --path force-app -v <DevHub Org Name>
sf package version create -p "DeploymentLens" -x --code-coverage -w 30 -v <DevHub Org Name>
sf package version promote -p "DeploymentLens@1.0.0-1" -v <DevHub Org Name>
```

`version create` prints the `04t…` Id — publish it on the Releases page so the
README install URLs work. Promotion requires ≥75% coverage (`--code-coverage`
must be passed at version create).

If the packaged External/Named Credential XML is rejected on deploy (schema
varies slightly by release), delete those two files and create both records
manually in Setup with the same API names — the Setup Assistant works either way.
