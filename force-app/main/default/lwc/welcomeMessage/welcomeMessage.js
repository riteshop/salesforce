import { LightningElement, wire } from 'lwc';
import getUserName from '@salesforce/apex/GetUser.getUserName'; 
// Or use getUserFirstName if you made that Apex method

export default class WelcomeMessage extends LightningElement {
    greeting;
    userName;

    @wire(getUserName)
    wiredUser({ data, error }) {
        if (data) {
            // Get only the first name (if full name returned)
            this.userName = data.split(' ')[0];

            // Compute greeting
            const hour = new Date().getHours();
            if (hour < 12) {
                this.greeting = 'Good morning';
            } else if (hour < 18) {
                this.greeting = 'Good afternoon';
            } else {
                this.greeting = 'Good evening';6
            }
        } else if (error) {
            this.userName = 'User';
            this.greeting = 'Hello';
        }
    }

    get fullGreeting() {
        return `${this.greeting}, ${this.userName}!`;
    }
}