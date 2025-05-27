import {onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

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