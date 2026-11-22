import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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

    async handleCopy(event) {
        const value = event.currentTarget.dataset.value;
        if (!value) { return; }

        let copied = false;
        // The async Clipboard API is often unavailable or blocked inside Lightning
        // (Locker/LWS, iframes, permissions policy), so fall back to execCommand.
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(value);
                copied = true;
            }
        } catch (e) {
            copied = false;
        }
        if (!copied) { copied = this.copyWithTextarea(value); }

        this.dispatchEvent(new ShowToastEvent({
            title: copied ? 'Copied' : 'Copy failed',
            message: copied ? value : 'Select the value and copy it manually.',
            variant: copied ? 'success' : 'error'
        }));
    }

    copyWithTextarea(value) {
        const host = this.template.querySelector('.copy-host');
        if (!host) { return false; }
        const textarea = document.createElement('textarea');
        textarea.value = value;
        textarea.setAttribute('readonly', '');
        textarea.style.position = 'fixed';
        textarea.style.top = '0';
        textarea.style.left = '0';
        textarea.style.opacity = '0';
        host.appendChild(textarea);
        let ok = false;
        try {
            textarea.focus();
            textarea.select();
            textarea.setSelectionRange(0, value.length);
            ok = document.execCommand('copy');
        } catch (e) {
            ok = false;
        } finally {
            host.removeChild(textarea);
        }
        return ok;
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
