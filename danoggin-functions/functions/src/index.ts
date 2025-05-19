import {onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
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
    });

    res.status(200).send(`Notification sent successfully: ${result}`);
  } catch (error) {
    console.error("Error sending notification:", error);
    res.status(500).send(`Error: ${error}`);
  }
});

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

    for (const observerId of observerIds) {
      const observerDoc = await admin.firestore()
        .collection("users").doc(observerId).get();

      if (observerDoc.exists) {
        const observerData = observerDoc.data();

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

    // Send individual notifications instead of using sendMulticast
    let successCount = 0;
    let failureCount = 0;
    const failedTokens: string[] = [];

    for (const token of allTokens) {
      try {
        await admin.messaging().send({
          notification: {
            title: title,
            body: body,
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
      } catch (error: unknown) {
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
