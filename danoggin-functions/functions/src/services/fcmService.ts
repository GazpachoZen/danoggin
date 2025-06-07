import * as admin from "firebase-admin";
import { removeTokenFromUser } from "../services/tokenCleanupService";
import { logTokenFailureForAnalytics, logTokenSuccess } from "./tokenHealthService";

// In-memory event collection for batched metrics
interface TokenEvent {
  userId: string;
  userName?: string;
  token: string;
  eventType: 'removal' | 'error' | 'strike';
  reason: string;
  details: any;
  context: string;
  timestamp: string;
}

// Global array to collect events during function execution
let tokenEvents: TokenEvent[] = [];

/**
 * Add a token event to the in-memory collection
 */
function addTokenEvent(event: TokenEvent): void {
  tokenEvents.push(event);

  // If we have too many events, flush them to prevent memory issues
  if (tokenEvents.length >= 100) {
    flushTokenEvents().catch(error =>
      console.error('Error flushing token events:', error)
    );
  }
}

/**
 * Flush collected token events to Firestore for batch processing
 */
async function flushTokenEvents(): Promise<void> {
  if (tokenEvents.length === 0) return;

  try {
    const batch = admin.firestore().batch();
    const eventsCollection = admin.firestore().collection('token_events');

    for (const event of tokenEvents) {
      const docRef = eventsCollection.doc(); // Auto-generated ID
      batch.set(docRef, event);
    }

    await batch.commit();
    console.log(`Flushed ${tokenEvents.length} token events to Firestore`);

    // Clear the in-memory array
    tokenEvents = [];

  } catch (error) {
    console.error('Error flushing token events to Firestore:', error);
    // Don't clear the array if flush failed - try again later
  }
}

/**
 * Send FCM check-in reminder to a responder
 */
export async function sendCheckInReminder(
  responderId: string,
  responderName: string,
  responderData: object
): Promise<void> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const data = responderData as any;
    // Get FCM tokens for the responder
    const fcmTokens = data.fcmTokens || [];
    const validTokens: string[] = [];

    for (const tokenData of fcmTokens) {
      if (typeof tokenData === "object" && tokenData.token) {
        validTokens.push(tokenData.token);
      }
    }

    if (validTokens.length === 0) {
      console.log(`No valid FCM tokens found for responder ${responderName}`);
      return;
    }

    console.log(
      `Sending check-in reminder to ${validTokens.length} devices ` +
      `for ${responderName}`
    );

    // Get current badge count for responder
    const userDoc = await admin.firestore().collection('users').doc(responderId).get();
    const currentBadge = userDoc.data()?.badgeCount || 0;
    const newBadgeCount = currentBadge + 1;

    // Update badge count in Firestore
    await admin.firestore().collection('users').doc(responderId).update({
      badgeCount: newBadgeCount,
      lastBadgeUpdate: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send notification to each token individually
    let successCount = 0;
    let failureCount = 0;

    for (const token of validTokens) {
      try {
        await admin.messaging().send({
          notification: {
            title: "Danoggin Check-In",
            body: "Time to answer a quick question!",
          },
          apns: {  // iOS-specific configuration
            payload: {
              aps: {
                sound: "default",
                badge: newBadgeCount,
                alert: {
                  title: "Danoggin Check-In",
                  body: "Time to answer a quick question!"
                }
              }
            }
          },
          android: {  // Android-specific configuration
            notification: {
              sound: "default",
              priority: "high",
              channelId: "danoggin_alerts"
            }
          },
          data: {
            type: "check_in_reminder",
            responderId: responderId,
            timestamp: new Date().toISOString(),
          },
          token: token,
        });
        successCount++;
        await logTokenSuccess(responderId, 'check_in_reminder');
        await resetTokenStrikes(responderId, token);

      } catch (error) {
        failureCount++;
        console.log(
          `Failed to send to token ${token.substring(0, 10)}...: ${error}`
        );

        // Log for analytics
        await logTokenFailureForAnalytics(
          responderId,
          token,
          error,
          'check_in_reminder'
        );

        // Handle token strikes based on error type
        await handleTokenError(responderId, token, error, 'check_in_reminder');
      }
    }

    console.log(
      `Check-in reminder sent: ${successCount} successful, ` +
      `${failureCount} failed`
    );
    await ensureTokenEventsFlushed();
  } catch (error) {
    console.error("Error sending check-in reminder:", error);
    // Still try to flush events even if there was an error
    await ensureTokenEventsFlushed();
    throw error;
  }
}

/**
 * Calculate and update the next check-in time for a responder
 */
export async function updateNextCheckInTime(
  responderId: string,
  responderData: object
): Promise<void> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const data = responderData as any;
    const checkInSettings = data.checkInSettings || {};
    const intervalMinutes = checkInSettings.intervalMinutes || 5;

    // Calculate next check-in time (current time + interval)
    const now = new Date();
    const nextCheckInTime = new Date(now.getTime() + intervalMinutes * 60000);

    console.log(
      "Updating next check-in time for responder to: " +
      `${nextCheckInTime.toISOString()}`
    );

    // Update the user document
    await admin.firestore().collection("users").doc(responderId).update({
      "checkInSettings.nextCheckInTime":
        admin.firestore.Timestamp.fromDate(nextCheckInTime),
      "checkInSettings.lastUpdated":
        admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("Next check-in time updated successfully");
  } catch (error) {
    console.error("Error updating next check-in time:", error);
    throw error;
  }
}

/**
 * Reschedule a responder's check-in for the next active period
 */
export async function rescheduleForNextActivePeriod(
  responderId: string,
  responderData: object
): Promise<void> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const data = responderData as any;
    const activeHours = data.activeHours || {};
    const startHour = activeHours.startHour || "08:00";

    // Parse start hour
    const [startH, startM] = startHour.split(":").map(Number);

    // Calculate next active start time (tomorrow at start hour)
    const now = new Date();
    const nextActiveStart = new Date(now);
    nextActiveStart.setUTCDate(now.getUTCDate() + 1);
    nextActiveStart.setUTCHours(startH, startM, 0, 0);

    console.log(
      "Rescheduling check-in for next active period: " +
      `${nextActiveStart.toISOString()}`
    );

    // Update the user document
    await admin.firestore().collection("users").doc(responderId).update({
      "checkInSettings.nextCheckInTime":
        admin.firestore.Timestamp.fromDate(nextActiveStart),
      "checkInSettings.lastUpdated":
        admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("Check-in rescheduled for next active period");
  } catch (error) {
    console.error("Error rescheduling for next active period:", error);
    throw error;
  }
}

/**
 * Send FCM notifications to observers about a responder's check-in issue
 */
export async function notifyObserversOfCheckInIssue(
  observerIds: string[],
  responderName: string,
  result: string,
  prompt: string,
  timestamp: string,
  checkInId: string
): Promise<void> {
  if (observerIds.length === 0) {
    console.log("No observers to notify");
    return;
  }

  try {
    // Get FCM tokens for all observers
    const allTokens: string[] = [];
    const invalidTokens: { [userId: string]: string[] } = {};
    const observerBadgeUpdates: { [userId: string]: number } = {};

    for (const observerId of observerIds) {
      const observerDoc = await admin.firestore()
        .collection("users").doc(observerId).get();

      if (observerDoc.exists) {
        const observerData = observerDoc.data();

        // Get current badge count and increment
        const currentBadge = observerData?.badgeCount || 0;
        const newBadgeCount = currentBadge + 1;
        observerBadgeUpdates[observerId] = newBadgeCount;

        // Extract tokens from the new fcmTokens array structure
        const fcmTokens = observerData?.fcmTokens || [];
        const validTokens: string[] = [];

        for (const tokenData of fcmTokens) {
          if (typeof tokenData === "object" && tokenData.token) {
            // Check if token is not too old (clean up old tokens)
            const tokenAge = Date.now() -
              new Date(tokenData.createdAt).getTime();
            const maxAge = 270 * 24 * 60 * 60 * 1000; // 270 days in ms

            if (tokenAge < maxAge) {
              validTokens.push(tokenData.token);
              allTokens.push(tokenData.token);
            } else {
              console.log(
                `Token for observer ${observerId} is older than 270 days, ` +
                "skipping"
              );
              // Track for potential cleanup
              if (!invalidTokens[observerId]) {
                invalidTokens[observerId] = [];
              }
              invalidTokens[observerId].push(tokenData.token);
            }
          }
        }

        console.log(
          `Observer ${observerId} has ${validTokens.length} valid FCM tokens`
        );
      }
    }

    if (allTokens.length === 0) {
      console.log("No valid FCM tokens found for observers");
      return;
    }

    // Format the timestamp
    const checkInTime = new Date(timestamp);
    const timeStr = checkInTime.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    });

    // Create notification message
    const title = `Danoggin Alert: ${result} check-in`;
    const body = `${responderName} ${result} a check-in at ${timeStr}`;

    // Update badge counts for all observers first
    const badgeUpdatePromises = Object.entries(observerBadgeUpdates).map(([observerId, badgeCount]) =>
      admin.firestore().collection('users').doc(observerId).update({
        badgeCount: badgeCount,
        lastBadgeUpdate: admin.firestore.FieldValue.serverTimestamp(),
      })
    );

    await Promise.all(badgeUpdatePromises);

    // Send individual notifications instead of using sendMulticast
    let successCount = 0;
    let failureCount = 0;
    const failedTokens: string[] = [];

    for (const token of allTokens) {
      try {
        // Find which observer this token belongs to for badge count
        let badgeCount = 1; // Default
        for (const [observerId, count] of Object.entries(observerBadgeUpdates)) {
          const observerDoc = await admin.firestore().collection('users').doc(observerId).get();
          const observerData = observerDoc.data();
          const fcmTokens = observerData?.fcmTokens || [];

          const hasToken = fcmTokens.some((tokenData: any) =>
            typeof tokenData === "object" && tokenData.token === token
          );

          if (hasToken) {
            badgeCount = count;
            break;
          }
        }

        await admin.messaging().send({
          notification: {
            title: title,
            body: body,
          },
          apns: {  // iOS-specific configuration
            payload: {
              aps: {
                sound: "default",
                badge: badgeCount,
                alert: {
                  title: title,
                  body: body
                }
              }
            }
          },
          android: {  // Android-specific configuration
            notification: {
              sound: "default",
              priority: "high",
              channelId: "danoggin_alerts"
            }
          },
          data: {
            type: "check_in_alert",
            responderName: responderName,
            result: result,
            timestamp: timestamp,
            checkInId: checkInId,
          },
          token: token,
        });
        successCount++;
        console.log(`Successfully sent to token ${token.substring(0, 10)}...`);

        // Find the observer ID for this token (used for both strike reset and analytics)
        let observerId = '';
        for (const [id, _count] of Object.entries(observerBadgeUpdates)) {
          const observerDoc = await admin.firestore().collection('users').doc(id).get();
          const observerData = observerDoc.data();
          const fcmTokens = observerData?.fcmTokens || [];

          const hasToken = fcmTokens.some((tokenData: any) =>
            typeof tokenData === "object" && tokenData.token === token
          );

          if (hasToken) {
            observerId = id;
            break;
          }
        }

        if (observerId) {
          // Reset strikes after successful send ("all is forgiven")
          await resetTokenStrikes(observerId, token);
          // Log successful notification for analytics
          await logTokenSuccess(observerId, 'observer_alert');
        }

      } catch (error) {
        failureCount++;
        failedTokens.push(token);
        console.log(
          `Failed to send to token ${token.substring(0, 10)}...: ${error}`
        );

        // Find which observer this token belongs to for proper error handling
        let observerId = '';
        for (const [id, _count] of Object.entries(observerBadgeUpdates)) {
          const observerDoc = await admin.firestore().collection('users').doc(id).get();
          const observerData = observerDoc.data();
          const fcmTokens = observerData?.fcmTokens || [];

          const hasToken = fcmTokens.some((tokenData: any) =>
            typeof tokenData === "object" && tokenData.token === token
          );

          if (hasToken) {
            observerId = id;
            break;
          }
        }

        if (observerId) {
          // Handle token error with strike system instead of immediate removal
          await handleTokenError(observerId, token, error, 'observer_alert');
        }
      }
    }

    console.log(`Notification sent to ${successCount} devices`);
    console.log(`Failed to send to ${failureCount} devices`);
    // Ensure all events are flushed to Firestore
    await ensureTokenEventsFlushed();

  } catch (error) {
    console.error("Error sending observer notifications:", error);
    // Still try to flush events even if there was an error
    await ensureTokenEventsFlushed();
    throw error;
  }
}


/**
 * Handle FCM token errors with intelligent strike system
 * Only removes tokens for definitive invalidity, logs everything else
 */
export async function handleTokenError(
  userId: string,
  token: string,
  error: any,
  context: string
): Promise<void> {
  try {
    // Extract error code from the error object
    const errorCode = error?.code || error?.errorInfo?.code || 'unknown';
    const errorMessage = error?.message || error?.errorInfo?.message || 'Unknown error';

    console.log(`Token error for user ${userId}: ${errorCode} - ${errorMessage}`);

    // Categorize errors into definitive invalidity vs temporary issues
    const definitivelyInvalidCodes = [
      'messaging/invalid-registration-token',
      'messaging/registration-token-not-registered',
      'messaging/mismatched-credential'
    ];

    if (definitivelyInvalidCodes.includes(errorCode)) {
      // This is definitely an invalid token - apply strike
      console.log(`Applying strike for invalid token: ${errorCode}`);
      await applyTokenStrike(userId, token, errorCode, context);
    } else {
      // This might be temporary (network, FCM service issues, etc.)
      // Log for metrics but don't penalize the token
      console.log(`Temporary error logged (no strike): ${errorCode}`);
      await logTemporaryTokenError(userId, token, errorCode, errorMessage, context);
    }

  } catch (handlingError) {
    console.error(`Error handling token error for user ${userId}:`, handlingError);
    // Don't let error handling break the main flow
  }
}

/**
 * Apply a strike to a token and remove if threshold reached
 */
export async function applyTokenStrike(
  userId: string,
  token: string,
  errorCode: string,
  context: string
): Promise<void> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      console.log(`User ${userId} not found for token strike`);
      return;
    }

    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || [];
    let tokenRemoved = false;
    let newStrikes = 0;

    // Find and update the specific token's strike count
    const updatedTokens = fcmTokens.map((tokenData: any) => {
      if (typeof tokenData === "object" && tokenData.token === token) {
        const currentStrikes = tokenData.strikes || 0;
        newStrikes = currentStrikes + 1;

        console.log(`Token strike ${newStrikes} for user ${userId} (${errorCode})`);

        // Remove token if it reaches strike threshold (3 strikes)
        if (newStrikes >= 3) {
          console.log(`Token removed after ${newStrikes} strikes for user ${userId}`);
          tokenRemoved = true;
          return null; // Mark for removal
        } else {
          // Update strike count and last strike info
          return {
            ...tokenData,
            strikes: newStrikes,
            lastStrike: {
              errorCode: errorCode,
              timestamp: new Date().toISOString(),
              context: context
            }
          };
        }
      }
      return tokenData;
    }).filter((tokenData: any) => tokenData !== null); // Remove null entries

    // Update the user document with modified tokens
    await admin.firestore().collection('users').doc(userId).update({
      fcmTokens: updatedTokens,
    });

    // Log events after the map operation (async operations allowed here)
    if (newStrikes > 0) {
      // Log the strike event for metrics
      try {
        let userName = 'Unknown User';
        if (userDoc.exists) {
          userName = userDoc.data()?.name || 'Unknown User';
        }

        addTokenEvent({
          userId: userId,
          userName: userName,
          token: token.substring(0, 10) + '...',
          eventType: 'strike',
          reason: errorCode,
          details: {
            strikeNumber: newStrikes,
            totalStrikes: newStrikes,
          },
          context: context,
          timestamp: new Date().toISOString(),
        });
      } catch (logError: any) {
        console.log(`Error logging strike event: ${logError}`);
      }

      // Log removal if token was removed
      if (tokenRemoved) {
        await logTokenRemoval(userId, token, 'strike_threshold', newStrikes, context);
        console.log(`Successfully removed token after strikes for user ${userId}`);
      }
    }

  } catch (error) {
    console.error(`Error applying token strike for user ${userId}:`, error);
  }
}

/**
 * Log temporary token errors for metrics without applying strikes
 */
export async function logTemporaryTokenError(
  userId: string,
  token: string,
  errorCode: string,
  errorMessage: string,
  context: string
): Promise<void> {
  try {
    console.log(`Temporary token error logged: User=${userId}, Error=${errorCode}, Context=${context}`);

    // Get user name for better metrics tracking
    let userName = 'Unknown User';
    try {
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (userDoc.exists) {
        userName = userDoc.data()?.name || 'Unknown User';
      }
    } catch (userError) {
      console.log(`Could not fetch user name for ${userId}:`, userError);
    }

    // Add to in-memory event collection
    addTokenEvent({
      userId: userId,
      userName: userName,
      token: token.substring(0, 10) + '...', // Only store token prefix for privacy
      eventType: 'error',
      reason: errorCode,
      details: {
        errorMessage: errorMessage,
        temporary: true,
      },
      context: context,
      timestamp: new Date().toISOString(),
    });

  } catch (error: any) {
    console.error(`Error logging temporary token error:`, error);
  }
}

/**
 * Log token removal events for metrics tracking
 */
export async function logTokenRemoval(
  userId: string,
  token: string,
  reason: string,
  details: any,
  context: string
): Promise<void> {
  try {
    console.log(`Token removal logged: User=${userId}, Reason=${reason}, Details=${details}, Context=${context}`);

    // Get user name for better metrics tracking
    let userName = 'Unknown User';
    try {
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (userDoc.exists) {
        userName = userDoc.data()?.name || 'Unknown User';
      }
    } catch (userError) {
      console.log(`Could not fetch user name for ${userId}:`, userError);
    }

    // Add to in-memory event collection
    addTokenEvent({
      userId: userId,
      userName: userName,
      token: token.substring(0, 10) + '...', // Only store token prefix for privacy
      eventType: 'removal',
      reason: reason,
      details: details,
      context: context,
      timestamp: new Date().toISOString(),
    });

  } catch (error: any) {
    console.error(`Error logging token removal:`, error);
  }
}

/**
 * Reset strike count for a token after successful send
 * Implements "all is forgiven" policy
 */
export async function resetTokenStrikes(userId: string, token: string): Promise<void> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      return;
    }

    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || [];

    // Find and reset strikes for the specific token
    const updatedTokens = fcmTokens.map((tokenData: any) => {
      if (typeof tokenData === "object" && tokenData.token === token) {
        if (tokenData.strikes && tokenData.strikes > 0) {
          console.log(`Resetting ${tokenData.strikes} strikes for user ${userId} after successful send`);
          // Remove strike-related fields since send was successful
          const { strikes, lastStrike, ...cleanTokenData } = tokenData;
          return cleanTokenData;
        }
      }
      return tokenData;
    });

    // Update the user document
    await admin.firestore().collection('users').doc(userId).update({
      fcmTokens: updatedTokens,
    });

  } catch (error) {
    console.error(`Error resetting token strikes for user ${userId}:`, error);
    // Don't let this break the main flow
  }
}

/**
 * Ensure all token events are flushed at the end of function execution
 * Should be called at the end of main FCM functions
 */
export async function ensureTokenEventsFlushed(): Promise<void> {
  if (tokenEvents.length > 0) {
    console.log(`Flushing remaining ${tokenEvents.length} token events at function end`);
    await flushTokenEvents();
  }
}
