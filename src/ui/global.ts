/**
 * Script-tag build: `dist/feedbackkit-ui.global.js` exposes `window.FeedbackKitUI`
 * with the client and the list embed, for pages without a bundler.
 */

export { FeedbackKit } from '../client';
export { FeedbackSort, FeedbackStatus, FeedbackCategory } from '../models/types';
export * from './index';
