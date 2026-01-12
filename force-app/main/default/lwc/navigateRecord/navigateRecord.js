import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport'; // Add this

export default class NavigateRecord extends NavigationMixin(LightningElement) {
    @api recordId;

    @api invoke() {
        // 1. Navigate to the record
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                actionName: 'view'
            }
        });

        // 2. Tell the flow to finish so it doesn't restart
        const navigateFinishEvent = new FlowNavigationFinishEvent();
        this.dispatchEvent(navigateFinishEvent);
    }
}