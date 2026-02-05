/**
 * IntegrationPicker - Handles cascading dropdown pickers for integrations
 */
class IntegrationPicker {
    constructor(options) {
        this.projectId = options.projectId;
        this.integration = options.integration;
        this.tokenFieldId = options.tokenFieldId;
        this.pickers = options.pickers || [];
        this.onComplete = options.onComplete || function() {};
        this.values = {};

        this.init();
    }

    init() {
        const tokenField = document.getElementById(this.tokenFieldId);
        if (!tokenField) {
            console.error('Token field not found:', this.tokenFieldId);
            return;
        }

        // Load first picker if token exists
        if (tokenField.value) {
            this.loadPicker(0);
        }

        // Listen for token changes
        tokenField.addEventListener('change', () => {
            if (tokenField.value) {
                this.loadPicker(0);
            }
        });

        // Also listen for blur (when user tabs away)
        tokenField.addEventListener('blur', () => {
            if (tokenField.value) {
                this.loadPicker(0);
            }
        });

        // Setup change listeners for each picker
        this.pickers.forEach((picker, index) => {
            const select = document.getElementById(`${this.integration}-${picker.id}`);
            if (select) {
                select.addEventListener('change', () => {
                    this.values[picker.id] = select.value;

                    // Load next picker if there is one
                    if (index < this.pickers.length - 1) {
                        this.loadPicker(index + 1);
                    } else {
                        // All pickers complete
                        this.onComplete(this.values);
                    }
                });
            }
        });
    }

    async loadPicker(index) {
        const picker = this.pickers[index];
        if (!picker) return;

        const container = document.getElementById(`${this.integration}-${picker.id}-container`);
        const select = document.getElementById(`${this.integration}-${picker.id}`);
        const errorDiv = document.getElementById(`${this.integration}-error`);

        if (!select) {
            console.error('Select element not found:', `${this.integration}-${picker.id}`);
            return;
        }

        // Show container
        if (container) {
            container.classList.remove('hidden');
        }

        // Build endpoint URL
        let endpoint = `/admin/projects/${this.projectId}/integrations/ajax/${this.integration}/${picker.endpoint}`;

        // Replace placeholders with actual values
        if (picker.dependsOn && this.values[picker.dependsOn]) {
            endpoint = endpoint.replace(`:${picker.dependsOn}Id`, this.values[picker.dependsOn]);
        }

        // Show loading state
        select.innerHTML = `<option value="">Loading...</option>`;
        select.disabled = true;

        try {
            const response = await fetch(endpoint);

            if (!response.ok) {
                const error = await response.json();
                throw new Error(error.reason || 'Failed to load data');
            }

            const data = await response.json();

            // Build options
            let options = `<option value="">Select ${picker.label}</option>`;
            data.forEach(item => {
                options += `<option value="${item.id}">${item.name}</option>`;
            });

            select.innerHTML = options;
            select.disabled = false;

            // Hide error
            if (errorDiv) {
                errorDiv.classList.add('hidden');
            }

            // Hide subsequent pickers
            for (let i = index + 1; i < this.pickers.length; i++) {
                const nextContainer = document.getElementById(`${this.integration}-${this.pickers[i].id}-container`);
                if (nextContainer) {
                    nextContainer.classList.add('hidden');
                }
            }

        } catch (error) {
            console.error('Error loading picker data:', error);
            select.innerHTML = `<option value="">Error loading data</option>`;
            select.disabled = false;

            // Show error message
            if (errorDiv) {
                errorDiv.classList.remove('hidden');
                errorDiv.querySelector('p').textContent = error.message;
            }
        }
    }
}
