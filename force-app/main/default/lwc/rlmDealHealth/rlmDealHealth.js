import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import inspectQuote from '@salesforce/apex/RLM_AI_DealDeskInspectService.inspectQuote';

import NAME_FIELD from '@salesforce/schema/Quote.Name';
import STATUS_FIELD from '@salesforce/schema/Quote.Status';
import ACCOUNT_NAME from '@salesforce/schema/Quote.Account.Name';
import PARTNER_NAME from '@salesforce/schema/Quote.PartnerAccount.Name';
import HEALTH_STATUS from '@salesforce/schema/Quote.RLM_Deal_Health_Status__c';
import HEALTH_FLAGS from '@salesforce/schema/Quote.RLM_Deal_Health_Flags__c';
import HEALTH_STEPS from '@salesforce/schema/Quote.RLM_Deal_Health_Next_Steps__c';
import BLENDED_MARGIN from '@salesforce/schema/Quote.RLM_Blended_Margin__c';
import LAST_RUN from '@salesforce/schema/Quote.RLM_Deal_Health_Last_Run__c';
import PC_JUSTIFICATION from '@salesforce/schema/Quote.RLM_PC_Justification__c';
import PC_COMPARE from '@salesforce/schema/Quote.RLM_PC_Compare_Summary__c';
import GRAND_TOTAL from '@salesforce/schema/Quote.GrandTotal';

const FIELDS = [
    NAME_FIELD,
    STATUS_FIELD,
    ACCOUNT_NAME,
    PARTNER_NAME,
    HEALTH_STATUS,
    HEALTH_FLAGS,
    HEALTH_STEPS,
    BLENDED_MARGIN,
    LAST_RUN,
    PC_JUSTIFICATION,
    PC_COMPARE,
    GRAND_TOTAL
];

export default class RlmDealHealth extends LightningElement {
    @api recordId;
    running = false;
    errorMessage;
    wiredQuote;
    autoRan = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredGetRecord(result) {
        this.wiredQuote = result;
        if (result && result.data && !this.autoRan && !this.running) {
            const last = getFieldValue(result.data, LAST_RUN);
            if (!last) {
                this.autoRan = true;
                this.handleRun();
            }
        }
    }

    get quote() {
        return this.wiredQuote && this.wiredQuote.data;
    }

    get loadError() {
        return this.wiredQuote && this.wiredQuote.error;
    }

    get quoteName() {
        return getFieldValue(this.quote, NAME_FIELD);
    }

    get quoteStatus() {
        return getFieldValue(this.quote, STATUS_FIELD);
    }

    get endCustomer() {
        return getFieldValue(this.quote, ACCOUNT_NAME) || 'Not set — DISTI account missing';
    }

    get partnerName() {
        return getFieldValue(this.quote, PARTNER_NAME) || '—';
    }

    get healthStatus() {
        return getFieldValue(this.quote, HEALTH_STATUS) || 'Not analyzed';
    }

    get flagsText() {
        return getFieldValue(this.quote, HEALTH_FLAGS) || 'Run analysis to populate flags.';
    }

    get stepsText() {
        return getFieldValue(this.quote, HEALTH_STEPS) || 'Run analysis for recommended next steps.';
    }

    get pcJustification() {
        return getFieldValue(this.quote, PC_JUSTIFICATION) || 'No PC justification yet. Use New Price Concession.';
    }

    get pcCompare() {
        return getFieldValue(this.quote, PC_COMPARE);
    }

    get lastRun() {
        const value = getFieldValue(this.quote, LAST_RUN);
        return value ? new Date(value).toLocaleString() : 'Never';
    }

    get marginLabel() {
        const value = getFieldValue(this.quote, BLENDED_MARGIN);
        if (value === null || value === undefined) {
            return '—';
        }
        const pct = value <= 1 ? value * 100 : value;
        return pct.toFixed(1) + '%';
    }

    get grandTotal() {
        const value = getFieldValue(this.quote, GRAND_TOTAL);
        return value == null ? '—' : new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    get statusClass() {
        const status = this.healthStatus;
        if (status === 'Healthy') {
            return 'status-pill status-healthy';
        }
        if (status === 'Review') {
            return 'status-pill status-review';
        }
        if (status === 'Risk') {
            return 'status-pill status-risk';
        }
        return 'status-pill status-unknown';
    }

    get flagLines() {
        return this.flagsText.split('\n').filter((line) => line);
    }

    get stepLines() {
        return this.stepsText.split('\n').filter((line) => line);
    }

    async handleRun() {
        this.running = true;
        this.errorMessage = null;
        try {
            const result = await inspectQuote({ quoteId: this.recordId });
            if (result && result.isSuccess === false) {
                this.errorMessage = result.errorMessage || 'Inspect failed.';
            } else if (this.wiredQuote) {
                await refreshApex(this.wiredQuote);
            }
        } catch (e) {
            this.errorMessage = e.body && e.body.message ? e.body.message : e.message;
        } finally {
            this.running = false;
        }
        if (this.errorMessage) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deal Health',
                message: this.errorMessage,
                variant: 'error'
            }));
        }
    }
}
