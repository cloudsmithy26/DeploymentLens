# Broker Snapshot Portwood templates

This folder holds the Portwood Word templates for two related, independent LWC features that
replace two legacy Visualforce pages:

| Legacy Visualforce page | Template | LWC | Apex controller |
| --- | --- | --- | --- |
| `WT_BrokerSnapshotDynamic.page` | `WT_Broker_Snapshot_Template.docx` | `wt_BrokerSnapshotDocGen` | `WT_BrokerSnapshotDocGenController` |
| `WT_BrokerSnapshotExternal.page` | `WT_Broker_Snapshot_External_Template.docx` | `wt_BrokerSnapshotExternalDocGen` | `WT_BrokerSnapshotExternalDocGenController` |

Both legacy pages actually shared one Apex controller (`WT_BrokerSnapshotDynamicController`)
and queried the same Account/Opportunity data — only the page markup (which fields it printed)
and the External page's extra usage-tracking action differed. The LWC migration keeps that
same relationship: **both templates merge against the same Apex data provider,
`WT_BrokerSnapshotDocGenProvider`** (an `portwoodglobal.DocGenDataProvider`) — the External
template simply references a subset of that provider's merge tags. Only the Apex *controller*
(the piece that resolves a template Id, calls Portwood, and returns a file to the LWC) is
duplicated, deliberately, once per variant, so the two document types can be configured,
retained and audited independently. See `getFieldNames()` on the provider for the full tag
list, and the Broker Snapshot Technical Design document
(`WT_Broker_Snapshot_Technical_Design.docx` in this folder) for the full old-field ->
short-tag mapping table.

Both templates use the same layout engine: General, Scorecard, e-Complete, Compensation,
Cross Selling and Added Value render as 3 label/value pairs per row (6 columns); Production
and Historical Production render as 1 pair per row — all within a single continuous table so
columns stay aligned across sections (see "Regenerating the templates" below). The External
template omits a handful of fields the legacy External page never printed (FIRST/Competitor
Usage, FIRST Competitor, Agency Development Program, Interest in Sports Tickets) and orders
Compensation fields to match that page's own layout.

## One-time setup in the org

1. Install/confirm the Portwood managed package (`portwoodglobal`) and deploy
   `WT_BrokerSnapshotDocGenProvider`, `WT_BrokerSnapshotDocGenController`,
   `WT_BrokerSnapshotExternalDocGenController`, the `WT_Broker_Snapshot_DocGen_Setting__mdt`
   Custom Metadata Type, the `WT_BrokerSnapshotPdfViewer` static resource, and both
   `wt_BrokerSnapshotDocGen` / `wt_BrokerSnapshotExternalDocGen` LWCs from this repo.
2. In the Portwood app → **New Template**, once per variant:
   - **Step 1 — Data Source**: choose **Apex Class (Data Provider)**, search for and select
     `WT_BrokerSnapshotDocGenProvider` (same class for both templates).
   - Upload `WT_Broker_Snapshot_Template.docx` for the Dynamic variant, or
     `WT_Broker_Snapshot_External_Template.docx` for the External variant.
   - Base object: Account. Output format: PDF.
   - Mark the template **Active**, then save it.
3. **Point each controller at its template**: open Setup → Custom Metadata Types →
   **WT Broker Snapshot DocGen Setting** → the `Default` record, and set:
   - **Template Id** to the Dynamic template's record Id (read by
     `WT_BrokerSnapshotDocGenController`).
   - **External Template Id** to the External template's record Id (read by
     `WT_BrokerSnapshotExternalDocGenController`).

   Both fields live on the same CMDT record — one settings record, two template pointers.
   Both are environment-specific (sandbox and production get different template Ids) and must
   be re-set after creating each template in a new environment.
4. Place `wt_BrokerSnapshotDocGen` and/or `wt_BrokerSnapshotExternalDocGen` on the Account
   Lightning Record Page (e.g. separate "Broker Snapshot" and "Broker Snapshot External" tabs)
   via Lightning App Builder — this repo has no existing Account Flexipage to deploy the
   placement declaratively, so it's a one-time manual step per org.
5. Confirm the running users' permission sets grant standard Files (ContentDocument /
   ContentVersion / ContentDocumentLink) create, read and delete access — each controller
   attaches its generated PDF to the Account and deletes its own older ones to enforce a
   keep-the-last-2 retention policy (Dynamic and External snapshots are tracked and retained
   separately, by file title, so generating one variant never prunes the other). Also confirm
   users generating an External snapshot have create access to
   `Broker_Snapshot_External_Usage__c` — every successful External generation logs one audit
   record there (`Executed_By__c` = the running user, `Executed_on_Agent_Broker__c` = the
   Account), mirroring what the legacy External page did on every render. (Custom Metadata
   Type records like `WT_Broker_Snapshot_DocGen_Setting__mdt` are readable by any
   authenticated user by default, so no additional permission is needed just to read the
   configured template Ids.)

## Viewing the generated PDF — two preview modes

Neither LWC can embed a PDF's bytes directly in its own markup via a Blob object URL —
Lightning Web Security blocks `<iframe src="blob:...">` outright. Both components ship **two**
preview options side by side, with a toggle, so you can compare them after deploying and settle
on one:

- **Standard Preview** (default) — opens Salesforce's own **File Preview** overlay via
  `NavigationMixin` (`standard__namedPage` / `filePreview`), the same modal a Files related
  list uses. Zero extra dependencies; always available.
- **Inline Viewer** — renders the PDF into `<canvas>` elements inside a same-origin
  (`https://`) `<iframe>` embedded directly in the component, using the
  `WT_BrokerSnapshotPdfViewer` static resource (Mozilla's official
  [pdf.js](https://mozilla.github.io/pdf.js/) core rendering library, Apache-2.0 — **not** the
  old, unmaintained third-party bundle some blog tutorials on this topic link to). LWS allows
  `window.postMessage` into a same-origin iframe even though it blocks `blob:` navigation, so
  the LWC posts the generated PDF's base64 bytes to the iframe once it reports itself ready;
  only files small enough to come back with inline base64 data (≤ ~3.5 MB — see
  `inlineDownloadMaxBytes` on each controller) can use this mode, and the LWC shows a message
  and falls back to Standard Preview / Download when a file is too large for it.

Both modes also feed a persistent file card (name + "Last generated on ...") and **Preview** /
**Download** buttons, so the user can reopen or download the current document at any time
without regenerating.

The `WT_BrokerSnapshotPdfViewer` static resource bundles only pdf.js's core library
(`build/pdf.mjs` + `build/pdf.worker.mjs`, source maps stripped, ~0.6 MB zipped) plus a small
custom `viewer.html` / `viewer.js` written for this project — deliberately **not** pdf.js's
full prebuilt toolbar/UI application, so the whole rendering pipeline (the `postMessage`
listener, the canvas rendering loop, the origin check) is code in this repo you can read
end to end, rather than an opaque bundled app.

## Regenerating the templates

Both `.docx` files were authored as raw OOXML (generated, not hand-typed in Word), using one
continuous table body for the whole document rather than several separate tables — this
sidesteps the "phantom width" column-drift issue Portwood's own User Guide (§5.8.1) calls out
for multi-table layouts, and keeps the 3-columns-per-row sections aligned with the
1-column-per-row sections (Production / Historical Production use `gridSpan` across the same
6-column grid rather than a second table). If you need to change field labels or layout,
editing directly in Word and re-saving is fine — just keep AutoFit set to **Fixed Column
Width** on every table so column widths don't drift.
