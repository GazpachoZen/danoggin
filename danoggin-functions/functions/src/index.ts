import {onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {initializeApp, getApps} from "firebase-admin/app";
import {getMessaging} from "firebase-admin/messaging";
import * as admin from "firebase-admin";

// Initialize Firebase Admin (only if not already initialized)
if (getApps().length === 0) {
  initializeApp();
}

/**
 * HTTP Cloud Function to test FCM notifications
 * Accepts token and message via GET or POST
 */
export const testFCM = onRequest(async (req, res) => {
  // Set CORS headers
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  // Handle preflight OPTIONS request
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  // Allow both GET and POST
  const {token, message} = req.method === "POST" ? req.body : req.query;

  if (!token) {
    res.status(400).send("Missing token parameter");
    return;
  }

  try {
    const result = await getMessaging().send({
      token: token as string,
      notification: {
        title: "Danoggin Test",
        body: (message as string) ||
          "Test notification from Cloud Functions",
      },
      apns: {  // iOS-specific configuration
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            alert: {
              title: "Danoggin Test",
              body: (message as string) ||
                "Test notification from Cloud Functions"
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
    });

    res.status(200).send(`Notification sent successfully: ${result}`);
  } catch (error) {
    console.error("Error sending notification:", error);
    res.status(500).send(`Error: ${error}`);
  }
});

/**
 * HTTP Cloud Function to clear badges for a user
 */
export const clearUserBadge = onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  const {userId} = req.body;

  if (!userId) {
    res.status(400).send("Missing userId parameter");
    return;
  }

  try {
    // Get user's FCM tokens
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      res.status(404).send("User not found");
      return;
    }

    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || [];
    
    // Send badge-clearing notification to all user's devices
    const promises = fcmTokens.map(async (tokenData: any) => {
      if (typeof tokenData === "object" && tokenData.token) {
        try {
          await admin.messaging().send({
            token: tokenData.token,
            apns: {
              payload: {
                aps: {
                  badge: 0,  // Clear the badge
                  "content-available": 1  // Silent notification
                }
              }
            },
            android: {
              data: {
                badgeCount: "0"
              }
            }
          });
        } catch (error) {
          console.log(`Failed to clear badge for token: ${error}`);
        }
      }
    });

    await Promise.all(promises);

    // Update Firestore badge count
    await admin.firestore().collection('users').doc(userId).update({
      badgeCount: 0,
      lastBadgeUpdate: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(200).send("Badge cleared successfully");
  } catch (error) {
    console.error("Error clearing badge:", error);
    res.status(500).send(`Error: ${error}`);
  }
});

/**
 * Scheduled function to send check-in reminders to responders
 * Runs every 5 minutes to check for due check-ins
 */
export const sendScheduledCheckInReminders = onSchedule({
  schedule: "*/5 * * * *", // Every 5 minutes
  timeZone: "UTC",
}, async () => {
  console.log("Starting scheduled check-in reminder process");

  try {
    const now = admin.firestore.Timestamp.now();
    console.log(`Checking for check-ins due before: ${now.toDate()}`);

    // Query for responders with due check-ins
    const usersRef = admin.firestore().collection("users");
    const dueCheckIns = await usersRef
      .where("role", "==", "responder")
      .where("checkInSettings.enabled", "==", true)
      .where("checkInSettings.nextCheckInTime", "<=", now)
      .get();

    console.log(`Found ${dueCheckIns.size} responders with due check-ins`);

    if (dueCheckIns.empty) {
      console.log("No check-ins due at this time");
      return;
    }

    // Process each due responder
    const results = await Promise.allSettled(
      dueCheckIns.docs.map((doc) => processResponderCheckIn(doc))
    );

    // Count results
    const successful = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;

    console.log(
      `Processed ${dueCheckIns.size} responders: ` +
      `${successful} successful, ${failed} failed`
    );
  } catch (error) {
    console.error("Error in scheduled check-in process:", error);
  }
});

/**
 * Process a single responder's due check-in
 * @param {object} responderDoc Firestore document snapshot of the responder
 * @return {Promise<void>} Promise that resolves when processing is complete
 */
async function processResponderCheckIn(
  responderDoc: admin.firestore.QueryDocumentSnapshot
): Promise<void> {
  const responderId = responderDoc.id;
  const responderData = responderDoc.data();
  const responderName = responderData.name || "Unknown Responder";

  console.log(`Processing check-in for responder: ${responderName}`);

  try {
    // Check if responder is within active hours
    if (!isWithinActiveHours(responderData)) {
      console.log(
        `Responder ${responderName} is outside active hours, ` +
        "rescheduling for next active period"
      );
      await rescheduleForNextActivePeriod(responderId, responderData);
      return;
    }

    // Send FCM notification
    await sendCheckInReminder(responderId, responderName, responderData);

    // Calculate and update next check-in time
    await updateNextCheckInTime(responderId, responderData);

    console.log(`Successfully processed check-in for ${responderName}`);
  } catch (error) {
    console.error(
      `Error processing check-in for responder ${responderName}:`,
      error
    );
    throw error;
  }
}

/**
 * Check if current time is within responder's active hours
 * @param {object} responderData The responder's Firestore document data
 * @return {boolean} True if within active hours, false otherwise
 */
function isWithinActiveHours(responderData: object): boolean {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = responderData as any;
  const activeHours = data.activeHours;
  if (!activeHours) {
    console.log("No active hours defined, assuming always active");
    return true;
  }

  const startHour = activeHours.startHour || "08:00";
  const endHour = activeHours.endHour || "20:00";

  try {
    // For simplicity, we'll use UTC comparison
    // In production, you'd want proper timezone conversion
    const now = new Date();
    const currentHour = now.getUTCHours();
    const currentMinute = now.getUTCMinutes();
    const currentTotalMinutes = currentHour * 60 + currentMinute;

    // Parse start and end hours
    const [startH, startM] = startHour.split(":").map(Number);
    const [endH, endM] = endHour.split(":").map(Number);
    const startTotalMinutes = startH * 60 + startM;
    const endTotalMinutes = endH * 60 + endM;

    // Check if current time is within active hours
    if (startTotalMinutes <= endTotalMinutes) {
      // Normal case (e.g., 08:00 to 20:00)
      return currentTotalMinutes >= startTotalMinutes &&
             currentTotalMinutes <= endTotalMinutes;
    } else {
      // Overnight case (e.g., 22:00 to 06:00)
      return currentTotalMinutes >= startTotalMinutes ||
             currentTotalMinutes <= endTotalMinutes;
    }
  } catch (error) {
    console.error("Error checking active hours:", error);
    return true; // Default to active if we can't determine
  }
}

/**
 * Send FCM check-in reminder to a responder
 * @param {string} responderId The responder's user ID
 * @param {string} responderName The responder's display name
 * @param {object} responderData The responder's Firestore document data
 * @return {Promise<void>} Promise that resolves when notification is sent
 */
async function sendCheckInReminder(
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
      } catch (error) {
        failureCount++;
        console.log(
          `Failed to send to token ${token.substring(0, 10)}...: ${error}`
        );
        // Remove invalid tokens
        await removeInvalidToken(responderId, token);
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
 * @param {string} responderId The responder's user ID
 * @param {object} responderData The responder's current Firestore document data
 * @return {Promise<void>} Promise that resolves when update is complete
 */
async function updateNextCheckInTime(
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
 * @param {string} responderId The responder's user ID
 * @param {object} responderData The responder's Firestore document data
 * @return {Promise<void>} Promise that resolves when reschedule is complete
 */
async function rescheduleForNextActivePeriod(
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
 * Remove an invalid FCM token from a user's document
 * @param {string} userId The user ID whose token should be removed
 * @param {string} invalidToken The invalid token to remove
 * @return {Promise<void>} Promise that resolves when token is removed
 */
async function removeInvalidToken(
  userId: string,
  invalidToken: string
): Promise<void> {
  try {
    const userDoc = await admin.firestore()
      .collection("users").doc(userId).get();

    if (userDoc.exists) {
      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || [];

      // Filter out the invalid token
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const updatedTokens = fcmTokens.filter((tokenData: any) => {
        return !(typeof tokenData === "object" &&
          tokenData.token === invalidToken);
      });

      // Update the document
      await admin.firestore().collection("users").doc(userId).update({
        fcmTokens: updatedTokens,
      });

      console.log(`Removed invalid token from user ${userId}`);
    }
  } catch (error) {
    console.error(`Error removing invalid token: ${error}`);
  }
}

/**
 * Firestore trigger that processes check-in results and sends alerts
 * Triggers on creation of documents in
 * responder_status/{responderId}/check_ins/{checkInId}
 */
export const processCheckInResult = onDocumentCreated(
  "responder_status/{responderId}/check_ins/{checkInId}",
  async (event) => {
    const snapshot = event.data;
    const checkInData = snapshot?.data();
    const responderId = event.params?.responderId;
    const checkInId = event.params?.checkInId;

    if (!checkInData || !responderId || !checkInId) {
      console.log("Missing required data in check-in event");
      return;
    }

    const {result, prompt, timestamp} = checkInData;

    console.log(`Processing check-in for responder ${responderId}: ${result}`);

    // Only send alerts for missed or incorrect check-ins
    if (result !== "missed" && result !== "incorrect") {
      console.log(`Check-in result is ${result} - no alert needed`);
      return;
    }

    try {
      // Get responder details
      const responderDoc = await admin.firestore()
        .collection("users").doc(responderId).get();

      if (!responderDoc.exists) {
        console.log(`Responder ${responderId} not found`);
        return;
      }

      const responderData = responderDoc.data();
      const responderName = responderData?.name || "Unknown Responder";
      const linkedObservers = responderData?.linkedObservers || {};

      console.log(
        `Found ${Object.keys(linkedObservers).length} linked observers`);

      // Send notifications to all linked observers
      await notifyObserversOfCheckInIssue(
        Object.keys(linkedObservers),
        responderName,
        result,
        prompt,
        timestamp,
        checkInId
      );
    } catch (error) {
      console.error("Error processing check-in result:", error);
      throw error;
    }
  });

/**
 * Send FCM notifications to observers about a responder's check-in issue
 * @param {string[]} observerIds Array of observer user IDs to notify
 * @param {string} responderName Name of the responder who had the issue
 * @param {string} result Type of check-in result (missed or incorrect)
 * @param {string} prompt The question that was missed/incorrectly answered
 * @param {string} timestamp ISO 8601 timestamp of when the check-in occurred
 * @param {string} checkInId Firestore document ID of the check-in record
 * @return {Promise<void>} Promise that resolves when notifications are sent
 */
async function notifyObserversOfCheckInIssue(
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
 * @param {string[]} failedTokens Array of tokens that failed to send
 * @param {string[]} observerIds Array of observer user IDs who should have
 *   tokens removed
 * @return {Promise<void>} Promise that resolves when cleanup is complete
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
 * @param {object} invalidTokens Map of user IDs to arrays of invalid tokens
 *   to remove
 * @return {Promise<void>} Promise that resolves when all old tokens are
 *   removed
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

/**
 * Remove a specific FCM token from a user's Firestore document
 * @param {string} userId The user ID whose document should be updated
 * @param {string} tokenToRemove The specific FCM token string to remove
 * @return {Promise<void>} Promise that resolves when the token is removed
 */
async function removeTokenFromUser(
  userId: string,
  tokenToRemove: string
): Promise<void> {
  try {
    const userDoc = await admin.firestore()
      .collection("users").doc(userId).get();

    if (userDoc.exists) {
      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || [];

      // Filter out the token to remove
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const updatedTokens = fcmTokens.filter((tokenData: any) => {
        return !(typeof tokenData === "object" &&
          tokenData.token === tokenToRemove);
      });

      // Update the document
      await admin.firestore().collection("users").doc(userId).update({
        fcmTokens: updatedTokens,
      });

      console.log(`Removed invalid token from user ${userId}`);
    }
  } catch (error) {
    console.error(`Error removing token from user ${userId}:`, error);
  }
}
