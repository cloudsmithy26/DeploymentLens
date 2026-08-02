import { LightningElement, wire } from 'lwc';
import getSetupInfo from '@salesforce/apex/DeploymentOverviewSetupController.getSetupInfo';
import testConnection from '@salesforce/apex/DeploymentOverviewSetupController.testConnection';

export default class SetupAssistant extends LightningElement {
    info;
    testResult;
    testing = false;

    @wire(getSetupInfo)
    wiredInfo({ data }) {
        if (data) { this.info = data; }
    }

    get resultBoxClass() {
        const base = 'slds-box slds-box_x-small slds-var-m-top_small ';
        return base + (this.testResult && this.testResult.status === 'Success'
            ? 'slds-theme_success' : 'slds-theme_error');
    }

    handleCopy(event) {
        const value = event.currentTarget.dataset.value;
        if (navigator.clipboard) { navigator.clipboard.writeText(value); }
    }

    async handleTest() {
        this.testing = true;
        this.testResult = undefined;
        try {
            this.testResult = await testConnection();
        } catch (e) {
            this.testResult = {
                status: 'Failed',
                detail: (e && e.body && e.body.message) || 'Unexpected error',
                hint: 'See the README troubleshooting section.'
            };
        } finally {
            this.testing = false;
        }
    }
}
