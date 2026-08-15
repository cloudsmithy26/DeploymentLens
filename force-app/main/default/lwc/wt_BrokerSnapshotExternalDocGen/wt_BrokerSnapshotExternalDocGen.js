import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import pdfViewerResource from '@salesforce/resourceUrl/WT_BrokerSnapshotPdfViewer';
import generate from '@salesforce/apex/WT_BrokerSnapshotExternalDocGenController.generate';
import getLatestBrokerSnapshot from '@salesforce/apex/WT_BrokerSnapshotExternalDocGenController.getLatestBrokerSnapshot';

// Lightning Web Security blocks <iframe src="blob:..."> outright, so a PDF's bytes cannot be
// embedded directly in this component via a Blob object URL. Three platform-compatible ways
// to show the file remain, and this component offers all three side by side (toggle) so they
// can be compared after deploying and narrowed down to one:
//   1. "Standard Preview" — Salesforce's own File Preview overlay via NavigationMixin, the
//      same modal a Files related list uses. Always available; no setup required.
//   2. "Inline (pdf.js)" — a same-origin (https://) iframe pointed at a small static resource
//      (WT_BrokerSnapshotPdfViewer, built on Mozilla's pdf.js core library, shared with the
//      Dynamic-variant component) that renders the PDF onto <canvas> elements. The generated
//      PDF's base64 bytes are handed to it via window.postMessage once it reports itself
//      ready. Only works for files small enough to come back with inline base64 data (see
//      WT_BrokerSnapshotExternalDocGenController.inlineDownloadMaxBytes).
//   3. "Inline (Simple)" — an iframe pointed directly at the file's own servlet download URL
//      (https://, same-origin — never blocked by LWS). This is Salesforce's own documented
//      pattern (see the Salesforce Developers blog "Display PDF Files with Lightning Web
//      Components"), but it renders inline only if the ORG is configured for it: Setup ->
//      Security -> File Upload and Download Security -> PDF -> Execute in Browser. ("Hybrid"
//      is not enough — it only executes legacy Attachments/Documents in-browser and still
//      downloads modern Salesforce Files, which is what ContentVersion/ContentDocument are.)
//      Until that setting is made, this mode will simply download the file instead of
//      showing it, which is expected and not a bug in this component.
const PDF_VIEWER_URL = `${pdfViewerResource}/viewer.html`;

const PREVIEW_MODE_STANDARD = 'standard';
const PREVIEW_MODE_PDFJS = 'pdfjs';
const PREVIEW_MODE_SERVLET = 'servlet';

// This component mirrors wt_BrokerSnapshotDocGen exactly, pointed at
// WT_BrokerSnapshotExternalDocGenController instead — kept as an independent copy (its own
// Apex controller, its own document title/retention, its own generated-record audit log via
// Broker_Snapshot_External_Usage__c) rather than a shared/parameterized component, matching
// the legacy pages' separation (WT_BrokerSnapshotDynamic.page vs WT_BrokerSnapshotExternal.page).
export default class Wt_BrokerSnapshotExternalDocGen extends NavigationMixin(LightningElement) {
    _recordId;
    _hasLoadedExistingDocument = false;
    _pendingInlineBase64Data;

    // Identity (not just a boolean) of the specific <iframe> DOM node that last reported
    // itself ready. The pdf.js iframe unmounts/remounts (a new DOM node, a fresh unloaded
    // document) whenever its lwc:if condition flips false->true — including indirectly, e.g.
    // a large (pdf.js-ineligible) generated file followed by a small one while the user stays
    // on the pdf.js mode the whole time. Comparing node identity, rather than tracking a
    // boolean that business-logic code would have to remember to reset on every such path,
    // makes "is the iframe currently in the DOM the same one that said VIEWER_READY" always
    // correct without enumerating every transition that (re)mounts it.
    _readyIframeElement;

    isGenerating = false;
    isLoadingExisting = false;
    errorMessage;

    hasDocument = false;
    fileName;
    generatedDateLabel;
    downloadUrl;
    downloadFileName;
    contentDocumentId;
    pdfBase64Data;

    previewMode = PREVIEW_MODE_STANDARD;
    pdfViewerUrl = PDF_VIEWER_URL;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadExistingDocumentOnce();
    }

    connectedCallback() {
        this._handleViewerMessage = this.handleViewerMessage.bind(this);
        window.addEventListener('message', this._handleViewerMessage);
    }

    disconnectedCallback() {
        window.removeEventListener('message', this._handleViewerMessage);
    }

    get isButtonDisabled() {
        return this.isGenerating || !this.recordId;
    }

    get generateButtonLabel() {
        return this.isGenerating ? 'Generating…' : 'Generate External Broker Snapshot PDF';
    }

    get isDownloadDisabled() {
        return this.isBusy || !this.hasDocument;
    }

    get isPreviewDisabled() {
        return this.isBusy || !this.hasDocument;
    }

    get isBusy() {
        return this.isGenerating || this.isLoadingExisting;
    }

    get showEmptyState() {
        return !this.hasDocument && !this.isLoadingExisting;
    }

    get isPdfjsModeSelected() {
        return this.previewMode === PREVIEW_MODE_PDFJS;
    }

    get isServletModeSelected() {
        return this.previewMode === PREVIEW_MODE_SERVLET;
    }

    get canUsePdfjsViewer() {
        return !!this.pdfBase64Data;
    }

    get showPdfjsViewer() {
        return this.isPdfjsModeSelected && this.hasDocument && this.canUsePdfjsViewer;
    }

    get showServletViewer() {
        return this.isServletModeSelected && this.hasDocument;
    }

    get standardPreviewButtonVariant() {
        return this.previewMode === PREVIEW_MODE_STANDARD ? 'brand' : 'neutral';
    }

    get pdfjsViewerButtonVariant() {
        return this.isPdfjsModeSelected ? 'brand' : 'neutral';
    }

    get servletViewerButtonVariant() {
        return this.isServletModeSelected ? 'brand' : 'neutral';
    }

    get pdfjsViewerUnavailableMessage() {
        return this.isPdfjsModeSelected && this.hasDocument && !this.canUsePdfjsViewer
            ? 'This file is too large for the pdf.js viewer — use another mode or Download instead.'
            : undefined;
    }

    get servletViewerHint() {
        return this.isServletModeSelected && this.hasDocument
            ? 'If this downloads the file instead of showing it, ask an admin to set Setup → Security → File Upload and Download Security → PDF → Execute in Browser.'
            : undefined;
    }

    /** Runs once recordId first becomes available (the record page injects it slightly
     *  after component construction), so a previously generated snapshot is found — and its
     *  preview opened — without the user having to click Generate first. */
    loadExistingDocumentOnce() {
        if (this._hasLoadedExistingDocument || !this.recordId) {
            return;
        }
        this._hasLoadedExistingDocument = true;
        this.loadExistingDocument();
    }

    async loadExistingDocument() {
        this.isLoadingExisting = true;
        try {
            const result = await getLatestBrokerSnapshot({ recordId: this.recordId });
            if (result && result.success) {
                this.applyDocumentResult(result, { openPreview: true });
            }
            // A failed lookup here just means no snapshot has been generated yet — that is
            // an expected first-time state, not an error worth surfacing to the user.
        } catch (error) {
            // Swallow: the initial "is there an existing document" check should never block
            // the user from generating a fresh one.
        } finally {
            this.isLoadingExisting = false;
        }
    }

    async handleGenerateClick() {
        this.isGenerating = true;
        this.errorMessage = undefined;
        try {
            const result = await generate({ recordId: this.recordId });
            if (!result || !result.success) {
                this.fail((result && result.errorMessage) || 'Document generation failed.');
                return;
            }
            this.applyDocumentResult(result, { openPreview: true });
            this.showToast('External Broker Snapshot generated', `${result.fileName} is ready.`, 'success');
        } catch (error) {
            this.fail(this.toMessage(error));
        } finally {
            this.isGenerating = false;
        }
    }

    /** Wires a generate()/getLatestBrokerSnapshot() result into the file card, then — unless
     *  told not to — shows it in whichever preview mode is currently selected. Both Apex
     *  methods return the same shape, so this one method handles a just-generated document
     *  and a previously generated document identically. */
    applyDocumentResult(result, { openPreview }) {
        this.hasDocument = true;
        this.fileName = result.fileName;
        this.downloadFileName = result.fileName;
        this.downloadUrl = result.downloadUrl;
        this.contentDocumentId = result.contentDocumentId;
        this.pdfBase64Data = result.base64Data;
        this.generatedDateLabel = this.formatGeneratedDate(result.generatedDate);

        if (openPreview) {
            this.showCurrentDocument();
        }
    }

    handlePreviewClick() {
        this.showCurrentDocument();
    }

    handleStandardPreviewSelected() {
        this.previewMode = PREVIEW_MODE_STANDARD;
        if (this.hasDocument) {
            this.openStandardFilePreview();
        }
    }

    handlePdfjsViewerSelected() {
        this.previewMode = PREVIEW_MODE_PDFJS;
        if (this.hasDocument && this.canUsePdfjsViewer) {
            this.renderPdfjsViewer();
        }
    }

    handleServletViewerSelected() {
        this.previewMode = PREVIEW_MODE_SERVLET;
        // No JS action needed: the servlet-viewer <iframe>'s src is template-bound to
        // downloadUrl directly, so it renders (or, until the org's PDF download setting is
        // switched to Execute in Browser, offers a download) as soon as it mounts.
    }

    /** Shows the current document using whichever preview mode is currently selected. */
    showCurrentDocument() {
        if (this.previewMode === PREVIEW_MODE_PDFJS) {
            this.renderPdfjsViewer();
        } else if (this.previewMode === PREVIEW_MODE_STANDARD) {
            this.openStandardFilePreview();
        }
        // PREVIEW_MODE_SERVLET needs no action here — see handleServletViewerSelected.
    }

    /** Opens the file in Salesforce's built-in File Preview overlay — the same "standard
     *  Files view" experience as clicking a file in a Files related list. */
    openStandardFilePreview() {
        if (!this.contentDocumentId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: this.contentDocumentId
            }
        });
    }

    /** Sends the current PDF's base64 bytes to the pdf.js iframe. If the iframe currently in
     *  the DOM is not the same node that last reported itself ready (VIEWER_READY) — either
     *  because it has never loaded yet, or because it was unmounted and a fresh one just
     *  remounted — the data is queued and flushed once the new one reports ready, avoiding a
     *  race where postMessage fires before the iframe's own listener is attached. */
    renderPdfjsViewer() {
        if (!this.pdfBase64Data) {
            return;
        }
        const currentIframe = this.template.querySelector('iframe.broker-snapshot-pdfjs-viewer');
        if (currentIframe && currentIframe === this._readyIframeElement) {
            this.postToViewer(this.pdfBase64Data);
        } else {
            this._pendingInlineBase64Data = this.pdfBase64Data;
        }
    }

    postToViewer(base64Data) {
        const iframe = this.template.querySelector('iframe.broker-snapshot-pdfjs-viewer');
        if (!iframe || !iframe.contentWindow) {
            return;
        }
        iframe.contentWindow.postMessage({ type: 'RENDER_PDF', base64: base64Data }, window.origin);
    }

    /** Handles VIEWER_READY / PDF_RENDERED / PDF_ERROR messages posted back by the pdf.js
     *  iframe. Origin-checked so only this component's own same-origin viewer iframe (not
     *  any other frame on the page) can drive this handler. */
    handleViewerMessage(event) {
        if (event.origin !== window.origin || !event.data) {
            return;
        }
        if (event.data.type === 'VIEWER_READY') {
            this._readyIframeElement = this.template.querySelector('iframe.broker-snapshot-pdfjs-viewer');
            if (this._pendingInlineBase64Data) {
                this.postToViewer(this._pendingInlineBase64Data);
                this._pendingInlineBase64Data = undefined;
            }
        } else if (event.data.type === 'PDF_ERROR') {
            this.showToast('pdf.js viewer could not render this document', event.data.message, 'error');
        }
    }

    handleDownloadClick() {
        if (!this.downloadUrl) {
            return;
        }
        const anchor = document.createElement('a');
        anchor.href = this.downloadUrl;
        anchor.download = this.downloadFileName || 'Broker Snapshot External.pdf';
        anchor.target = '_blank';
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
    }

    formatGeneratedDate(generatedDate) {
        if (!generatedDate) {
            return undefined;
        }
        return new Date(generatedDate).toLocaleString();
    }

    fail(message) {
        this.errorMessage = message;
        this.showToast('Could not generate External Broker Snapshot', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    toMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'Unexpected error.';
    }
}
