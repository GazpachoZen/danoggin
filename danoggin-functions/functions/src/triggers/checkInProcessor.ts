import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {notifyObserversOfCheckInIssue} from "../services/fcmService";

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