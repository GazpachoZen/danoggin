import * as admin from "firebase-admin";
import {removeTokenFromUser} from "../services/tokenCleanupService";
import {logTokenFailureForAnalytics, logTokenSuccess} from "./tokenHealthService";

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
        
        // Remove invalid tokens
        await removeTokenFromUser(responderId, token);
      }
    }

    console.log(
      `Check-in reminder sent: ${successCount} successful, ` +
      `${failureCount} failed`
    );
  } catch (error) {
    console.error("Error sending check-in reminder:", error);
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

        // Log successful notification for analytics
        // Find the observer ID for this token
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
          await logTokenSuccess(observerId, 'observer_alert');
        }

      } catch (error) {
        failureCount++;
        failedTokens.push(token);
        console.log(
          `Failed to send to token ${token.substring(0, 10)}...: ${error}`
        );
      }
    }

    console.log(`Notification sent to ${successCount} devices`);
    console.log(`Failed to send to ${failureCount} devices`);

    // Handle failed tokens - remove them from Firestore
    if (failedTokens.length > 0) {
      await cleanupFailedTokensIndividual(failedTokens, observerIds);
    }

    // Clean up old tokens that we identified earlier
    await cleanupOldTokens(invalidTokens);
  } catch (error) {
    console.error("Error sending observer notifications:", error);
    throw error;
  }
}

/**
 * Remove FCM tokens that failed to send notifications (individual method)
 */
async function cleanupFailedTokensIndividual(
  failedTokens: string[],
  observerIds: string[]
): Promise<void> {
  console.log("Cleaning up failed FCM tokens...");

  for (const failedToken of failedTokens) {
    console.log(
      `Removing invalid FCM token: ${failedToken.substring(0, 10)}...`
    );

    // Find which observer this token belongs to and remove it
    for (const observerId of observerIds) {
      await removeTokenFromUser(observerId, failedToken);
    }
  }
}

/**
 * Remove old/expired tokens from user documents
 */
async function cleanupOldTokens(
  invalidTokens: { [userId: string]: string[] }
): Promise<void> {
  for (const [userId, tokens] of Object.entries(invalidTokens)) {
    console.log(`Cleaning up ${tokens.length} old tokens for user ${userId}`);
    for (const token of tokens) {
      await removeTokenFromUser(userId, token);
    }
  }
}