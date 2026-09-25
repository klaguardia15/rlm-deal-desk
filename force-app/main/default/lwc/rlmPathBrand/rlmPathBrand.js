import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import zebraPathBrand from '@salesforce/resourceUrl/RLM_PathBrand';

export default class RlmPathBrand extends LightningElement {
    loaded = false;

    renderedCallback() {
        if (this.loaded) {
            return;
        }
        this.loaded = true;
        loadStyle(this, zebraPathBrand).catch((error) => {
            // eslint-disable-next-line no-console
            console.error('Path brand CSS failed to load', error);
        });
    }
}
