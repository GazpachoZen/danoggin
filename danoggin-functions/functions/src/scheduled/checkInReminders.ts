import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {sendCheckInReminder, updateNextCheckInTime, rescheduleForNextActivePeriod} from "../services/fcmService";
import {isWithinActiveHours} from "../utils/timeUtils";

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