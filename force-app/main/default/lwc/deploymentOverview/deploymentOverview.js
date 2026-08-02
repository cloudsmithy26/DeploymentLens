import { LightningElement, api } from 'lwc';

const LIMIT_OPTIONS = [
    { label: 'Last 5', value: '5' },
    { label: 'Last 10', value: '10' },
    { label: 'Last 20', value: '20' }
];

export default class DeploymentOverview extends LightningElement {
    /** Configurable via the App Builder property panel. */
    @api defaultRecordLimit = '10';

    recordLimit;
    searchId = '';
    activeSearchId = '';
    selectedDeploymentId;

    limitOptions = LIMIT_OPTIONS;

    connectedCallback() {
        this.recordLimit = this.defaultRecordLimit || '10';
    }

    get showList() {
        return !this.selectedDeploymentId;
    }

    get showDetail() {
        return !!this.selectedDeploymentId;
    }

    handleLimitChange(event) {
        this.recordLimit = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchId = event.detail.value;
        if (!this.searchId) {
            this.activeSearchId = '';
        }
    }

    handleSearchKeyUp(event) {
        if (event.key === 'Enter') {
            this.activeSearchId = (this.searchId || '').trim();
        }
    }

    handleSelect(event) {
        this.selectedDeploymentId = event.detail.deploymentId;
    }

    handleBack() {
        this.selectedDeploymentId = undefined;
    }
}
