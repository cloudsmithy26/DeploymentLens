import { LightningElement, api } from 'lwc';
import getRecentDeployments from '@salesforce/apex/DeploymentOverviewController.getRecentDeployments';
import findDeploymentById from '@salesforce/apex/DeploymentOverviewController.findDeploymentById';

const COLUMNS = [
    {
        type: 'button',
        typeAttributes: { label: { fieldName: 'id' }, name: 'view', variant: 'base' },
        label: 'Deployment Id',
        initialWidth: 220
    },
    { label: 'Status', fieldName: 'status', cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'Type', fieldName: 'deployType', initialWidth: 110 },
    { label: 'Started By', fieldName: 'createdByName' },
    { label: 'Started', fieldName: 'startDate', type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Components', fieldName: 'componentProgress', initialWidth: 120 },
    { label: 'Comp. Errors', fieldName: 'componentErrors', type: 'number', initialWidth: 120 },
    { label: 'Tests', fieldName: 'testProgress', initialWidth: 100 },
    { label: 'Test Errors', fieldName: 'testErrors', type: 'number', initialWidth: 110 }
];

export default class DeploymentList extends LightningElement {
    columns = COLUMNS;
    rows = [];
    error;
    isLoading = false;

    _limitSize = '10';
    _searchId = '';

    @api
    get limitSize() { return this._limitSize; }
    set limitSize(value) {
        this._limitSize = value || '10';
        this.load();
    }

    @api
    get searchId() { return this._searchId; }
    set searchId(value) {
        this._searchId = (value || '').trim();
        this.load();
    }

    get hasRows() {
        return !this.isLoading && !this.error && this.rows.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.error && this.rows.length === 0;
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const data = this._searchId
                ? await findDeploymentById({ deploymentId: this._searchId })
                : await getRecentDeployments({ limitSize: parseInt(this._limitSize, 10) });
            this.rows = (data || []).map((d) => ({
                ...d,
                deployType: d.checkOnly ? 'Validation' : 'Deploy',
                componentProgress: `${d.componentsDeployed} / ${d.componentsTotal}`,
                testProgress: `${d.testsCompleted} / ${d.testsTotal}`,
                statusClass:
                    d.status === 'Succeeded' ? 'slds-text-color_success'
                    : d.status === 'Failed' ? 'slds-text-color_error'
                    : ''
            }));
        } catch (e) {
            this.rows = [];
            this.error = (e && e.body && e.body.message) || 'Unable to load deployments.';
        } finally {
            this.isLoading = false;
        }
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view') {
            this.dispatchEvent(new CustomEvent('selectdeployment', {
                detail: { deploymentId: event.detail.row.id }
            }));
        }
    }
}
