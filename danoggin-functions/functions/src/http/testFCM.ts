import {onRequest} from "firebase-functions/v2/https";
import {getMessaging} from "firebase-admin/messaging";

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