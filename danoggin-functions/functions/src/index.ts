import {onRequest} from "firebase-functions/v2/https";
import {initializeApp, getApps} from "firebase-admin/app";
import {getMessaging} from "firebase-admin/messaging";

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
