import { LightningElement, api } from 'lwc';
import getDeploymentDetails from '@salesforce/apex/DeploymentOverviewController.getDeploymentDetails';

const SUCCESS_COLUMNS = [
    { label: 'Type', fieldName: 'componentType', initialWidth: 180 },
    { label: 'Name', fieldName: 'fullName' },
    { label: 'File', fieldName: 'fileName' },
    { label: 'Action', fieldName: 'action', initialWidth: 110 }
];

const FAILURE_COLUMNS = [
    { label: 'Type', fieldName: 'componentType', initialWidth: 180 },
    { label: 'Name', fieldName: 'fullName' },
    { label: 'Problem Type', fieldName: 'problemType', initialWidth: 130 },
    { label: 'Problem', fieldName: 'problem', wrapText: true }
];

const TEST_COLUMNS = [
    { label: 'Test Class', fieldName: 'apexClassName', initialWidth: 220 },
    { label: 'Method', fieldName: 'methodName' },
    { label: 'Outcome', fieldName: 'outcome', initialWidth: 100,
        cellAttributes: { class: { fieldName: 'outcomeClass' } } },
    { label: 'Time (ms)', fieldName: 'timeMs', type: 'number', initialWidth: 110 },
    { label: 'Message', fieldName: 'message', wrapText: true }
];

export default class DeploymentDetail extends LightningElement {
    successColumns = SUCCESS_COLUMNS;
    failureColumns = FAILURE_COLUMNS;
    testColumns = TEST_COLUMNS;

    detail;
    error;
    isLoading = false;
    filterTerm = '';

    _deploymentId;

    @api
    get deploymentId() { return this._deploymentId; }
    set deploymentId(value) {
        this._deploymentId = value;
        if (value) { this.load(); }
    }

    get statusLabel() { return this.detail ? this.detail.status : ''; }

    get statusBadgeClass() {
        if (!this.detail) { return ''; }
        if (this.detail.status === 'Succeeded') { return 'slds-badge slds-theme_success'; }
        if (this.detail.status === 'Failed') { return 'slds-badge slds-theme_error'; }
        return 'slds-badge';
    }

    get successes() {
        return (this.detail?.componentSuccesses || []).map((c, i) => ({
            ...c,
            key: `s-${i}`,
            action: c.created ? 'Created' : c.deleted ? 'Deleted' : c.changed ? 'Changed' : 'No change'
        }));
    }

    get filteredSuccesses() {
        const term = this.filterTerm.toLowerCase();
        if (!term) { return this.successes; }
        return this.successes.filter(
            (c) =>
                (c.fullName || '').toLowerCase().includes(term) ||
                (c.componentType || '').toLowerCase().includes(term)
        );
    }

    get failures() {
        return (this.detail?.componentFailures || []).map((c, i) => ({ ...c, key: `f-${i}` }));
    }

    get tests() {
        const pass = (this.detail?.testSuccesses || []).map((t, i) => ({
            ...t, key: `tp-${i}`, outcomeClass: 'slds-text-color_success'
        }));
        const fail = (this.detail?.testFailures || []).map((t, i) => ({
            ...t, key: `tf-${i}`, outcomeClass: 'slds-text-color_error'
        }));
        return [...fail, ...pass];
    }

    get successTabLabel() { return `Successes (${this.successes.length})`; }
    get failureTabLabel() { return `Failures (${this.failures.length})`; }
    get testTabLabel() { return `Apex Tests (${this.tests.length})`; }

    handleFilterChange(event) {
        this.filterTerm = event.detail.value || '';
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        this.detail = undefined;
        try {
            this.detail = await getDeploymentDetails({ deploymentId: this._deploymentId });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Unable to load deployment detail.';
        } finally {
            this.isLoading = false;
        }
    }
}
