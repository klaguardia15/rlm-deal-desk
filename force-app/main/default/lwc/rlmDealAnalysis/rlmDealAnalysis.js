import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import getPrompts from '@salesforce/apex/RLM_DealDeskService.getPrompts';
import applyAction from '@salesforce/apex/RLM_DealDeskService.applyAction';
import refreshPrices from '@salesforce/apex/RLM_DealDeskService.refreshPrices';
import compareQuotes from '@salesforce/apex/RLM_DealDeskService.compareQuotes';

export default class RlmDealAnalysis extends LightningElement {
    @api recordId;
    _showPrompts = true;
    _showCompare = true;

    @api
    get showPrompts() {
        return this._showPrompts;
    }
    set showPrompts(value) {
        this._showPrompts = this.toBool(value, true);
    }

    @api
    get showCompare() {
        return this._showCompare;
    }
    set showCompare(value) {
        this._showCompare = this.toBool(value, true);
    }

    loading = false;
    applying = false;
    comparing = false;
    errorMessage;
    headline;
    motionLabel;
    motionBody;
    prompts = [];
    quoteChoices = [];
    leftQuoteId;
    rightQuoteId;
    compareResult;
    compareError;
    changeFilters = ['Modified', 'Added', 'Removed'];
    scanned = false;

    renderedCallback() {
        if (!this.recordId || this.scanned || this.loading) {
            return;
        }
        this.scanned = true;
        this.loadPrompts();
    }

    toBool(value, fallback) {
        if (value === undefined || value === null || value === '') {
            return fallback;
        }
        if (value === true || value === 'true' || value === 'True') {
            return true;
        }
        if (value === false || value === 'false' || value === 'False') {
            return false;
        }
        return Boolean(value);
    }

    get promptsEnabled() {
        return this.showPrompts !== false;
    }

    get compareEnabled() {
        return this.showCompare !== false;
    }

    get showShell() {
        if (this.promptsEnabled) {
            return true;
        }
        if (this.errorMessage) {
            return true;
        }
        if (this.loading) {
            return false;
        }
        return this.canCompare;
    }

    get cardTitle() {
        return this.promptsEnabled ? 'Deal analysis' : 'Quote compare';
    }

    get hasPrompts() {
        return this.prompts && this.prompts.length;
    }

    get showBody() {
        return !this.loading && !this.errorMessage && (
            (this.promptsEnabled && (this.hasPrompts || this.motionLabel || this.headline)) ||
            this.canCompare
        );
    }

    get canCompare() {
        return this.compareEnabled && this.quoteChoices && this.quoteChoices.length >= 2;
    }

    get quoteOptions() {
        return (this.quoteChoices || []).map((choice) => ({
            label: choice.label,
            value: choice.id
        }));
    }

    get filterChips() {
        const result = this.compareResult || {};
        const selected = this.changeFilters || [];
        const chips = [
            { key: 'Modified', count: result.modifiedCount || 0, tone: 'chip-mod' },
            { key: 'Added', count: result.addedCount || 0, tone: 'chip-add' },
            { key: 'Removed', count: result.removedCount || 0, tone: 'chip-rem' },
            { key: 'Unchanged', count: result.unchangedCount || 0, tone: 'chip-ok' }
        ];
        return chips.map((chip) => {
            const on = selected.indexOf(chip.key) !== -1;
            return {
                key: chip.key,
                label: chip.count + ' ' + chip.key,
                title: on ? 'Hide ' + chip.key + ' lines' : 'Show ' + chip.key + ' lines',
                pressed: on ? 'true' : 'false',
                buttonClass: 'chip-btn ' + chip.tone + (on ? ' is-on' : ' is-off')
            };
        });
    }

    get visibleLineDeltas() {
        const rows = (this.compareResult && this.compareResult.lineDeltas) || [];
        const selected = this.changeFilters || [];
        const filtered = selected.length
            ? rows.filter((row) => selected.indexOf(row.changeType) !== -1)
            : rows;
        return filtered.map((line) => {
            const flag = line.marginFlag || 'margin-unknown';
            let flagLabel = 'Unknown';
            if (flag === 'margin-green') {
                flagLabel = 'Healthy';
            } else if (flag === 'margin-yellow') {
                flagLabel = 'Watch';
            } else if (flag === 'margin-red') {
                flagLabel = 'At risk';
            }
            return Object.assign({}, line, {
                flagClass: 'margin-pill ' + flag,
                flagLabel: flagLabel
            });
        });
    }

    get hasVisibleLines() {
        return this.visibleLineDeltas && this.visibleLineDeltas.length;
    }

    handleFilterChip(event) {
        const key = event.currentTarget.dataset.filter;
        if (!key) {
            return;
        }
        const next = (this.changeFilters || []).slice();
        const idx = next.indexOf(key);
        if (idx === -1) {
            next.push(key);
        } else {
            next.splice(idx, 1);
        }
        this.changeFilters = next;
    }

    async loadPrompts(skipStamp) {
        if (!this.recordId) {
            return;
        }
        this.loading = true;
        this.errorMessage = null;
        try {
            const result = await getPrompts({
                recordId: this.recordId,
                skipStamp: skipStamp === true
            });
            if (!result || result.isSuccess === false) {
                this.errorMessage = (result && result.errorMessage) || 'Could not scan this record.';
                this.prompts = [];
                this.headline = null;
                this.motionLabel = null;
                this.motionBody = null;
                this.quoteChoices = [];
            } else {
                this.headline = result.headline;
                this.motionLabel = result.motionLabel;
                this.motionBody = result.motionBody;
                this.prompts = (result.prompts || []).map((prompt) => {
                    const severity = prompt.severity || 'info';
                    return Object.assign({}, prompt, {
                        cardClass: 'prompt-card prompt-' + severity
                    });
                });
                this.quoteChoices = result.quoteChoices || [];
                this.leftQuoteId = result.defaultLeftId;
                this.rightQuoteId = result.defaultRightId;
                if (this.canCompare && this.leftQuoteId && this.rightQuoteId) {
                    await this.runCompare();
                }
            }
        } catch (e) {
            this.errorMessage = e.body && e.body.message ? e.body.message : e.message;
            this.prompts = [];
        } finally {
            this.loading = false;
        }
    }

    handleLeftChange(event) {
        this.leftQuoteId = event.detail.value;
    }

    handleRightChange(event) {
        this.rightQuoteId = event.detail.value;
    }

    async handleCompare() {
        await this.runCompare();
    }

    async runCompare() {
        if (!this.leftQuoteId || !this.rightQuoteId) {
            return;
        }
        this.comparing = true;
        this.compareError = null;
        try {
            const result = await compareQuotes({
                leftQuoteId: this.leftQuoteId,
                rightQuoteId: this.rightQuoteId
            });
            if (!result || result.isSuccess === false) {
                this.compareResult = null;
                this.compareError = (result && result.errorMessage) || 'Compare failed.';
            } else {
                this.compareResult = result;
            }
        } catch (e) {
            this.compareResult = null;
            this.compareError = e.body && e.body.message ? e.body.message : e.message;
        } finally {
            this.comparing = false;
        }
    }

    async handleApply(event) {
        const actionKey = event.currentTarget.dataset.action;
        if (!actionKey) {
            return;
        }
        this.applying = true;
        try {
            const result = await applyAction({
                recordId: this.recordId,
                actionKey: actionKey
            });
            if (!result || result.isSuccess === false) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Deal analysis',
                    message: (result && result.errorMessage) || 'Apply failed.',
                    variant: 'error'
                }));
            } else {
                let message = result.message;
                let pricedOk = false;
                try {
                    const priced = await refreshPrices({ recordId: this.recordId });
                    pricedOk = !!(priced && priced.isSuccess);
                    if (!pricedOk) {
                        message += ' Wait a moment, then click Refresh prices once.';
                    }
                } catch (priceErr) {
                    message += ' Wait a moment, then click Refresh prices once.';
                }
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Deal analysis',
                    message: message,
                    variant: pricedOk ? 'success' : 'warning'
                }));
                await new Promise((resolve) => setTimeout(resolve, 1200));
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.dispatchEvent(new RefreshEvent());
                await this.loadPrompts(true);
            }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deal analysis',
                message: e.body && e.body.message ? e.body.message : e.message,
                variant: 'error'
            }));
        } finally {
            this.applying = false;
        }
    }
}
