import {onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {initializeApp, getApps} from "firebase-admin/app";
import {getMessaging} from "firebase-admin/messaging";
import * as admin from "firebase-admin";

// Initialize Firebase Admin (only if not already initialized)
if (getApps().length === 0) {
  initializeApp();
}

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
        body: (message as string) || "Test notification from Cloud Functions",
      },
    });

    res.status(200).send(`Notification sent successfully: ${result}`);
  } catch (error) {
    console.error("Error sending notification:", error);
    res.status(500).send(`Error: ${error}`);
  }
});

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
 * Notifies observers about check-in issues via FCM
 * @param {string[]} observerIds Array of observer user IDs
 * @param {string} responderName Name of the responder
 * @param {string} result Check-in result (missed or incorrect)
 * @param {string} prompt The question prompt
 * @param {string} timestamp Check-in timestamp
 * @param {string} checkInId Check-in document ID
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
    const observerTokens: string[] = [];

    for (const observerId of observerIds) {
      const observerDoc = await admin.firestore()
        .collection("users").doc(observerId).get();

      if (observerDoc.exists) {
        const observerData = observerDoc.data();
        const token = observerData?.fcmToken;

        if (token) {
          observerTokens.push(token);
        }
      }
    }

    if (observerTokens.length === 0) {
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

    // Send notification to all observer tokens
    const message = {
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
      tokens: observerTokens,
    };

    const response = await admin.messaging().sendMulticast(message);

    console.log(`Notification sent to ${response.successCount} observers`);
    console.log(`Failed to send to ${response.failureCount} observers`);
  } catch (error) {
    console.error("Error sending observer notifications:", error);
    throw error;
  }
}
