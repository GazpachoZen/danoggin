import {initializeApp, getApps} from "firebase-admin/app";
import {processDailyTokenMetrics} from "./scheduled/metricsProcessor";

// Initialize Firebase Admin (only if not already initialized)
if (getApps().length === 0) {
  initializeApp();
}

// HTTP Functions
import {testFCM} from "./http/testFCM";
import {clearUserBadge} from "./http/clearUserBadge";

// Scheduled Functions
import {sendScheduledCheckInReminders} from "./scheduled/checkInReminders";
import {cleanupInvalidTokens} from "./scheduled/tokenCleanup";

// Firestore Triggers
import {processCheckInResult} from "./triggers/checkInProcessor";

// Re-export all functions
// Re-export all functions
export {
  testFCM,
  clearUserBadge,
  sendScheduledCheckInReminders,
  cleanupInvalidTokens,
  processCheckInResult,
  processDailyTokenMetrics,
};
