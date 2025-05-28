import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {removeTokenFromUser} from "../services/tokenCleanupService";

/**
 * Scheduled function to systematically clean up invalid FCM tokens
 * Runs weekly on Sunday at 2 AM UTC
 */
export const cleanupInvalidTokens = onSchedule({
  schedule: "0 2 * * 0", // Weekly on Sunday at 2 AM UTC
  timeZone: "UTC",
}, async () => {
  console.log("Starting systematic FCM token cleanup");

  try {
    let totalUsers = 0;
    let totalTokensChecked = 0;
    let totalTokensRemoved = 0;

    // Query all users with FCM tokens
    const usersSnapshot = await admin.firestore()
      .collection('users')
      .where('fcmTokens', '!=', [])
      .get();

    console.log(`Found ${usersSnapshot.size} users with FCM tokens`);

    // Process users in batches to avoid memory issues
    const batchSize = 50;
    const userDocs = usersSnapshot.docs;

    for (let i = 0; i < userDocs.length; i += batchSize) {
      const batch = userDocs.slice(i, i + batchSize);
      
      await Promise.all(batch.map(async (userDoc) => {
        const result = await cleanupUserTokens(userDoc.id, userDoc.data());
        totalUsers++;
        totalTokensChecked += result.checked;
        totalTokensRemoved += result.removed;
      }));

      // Add a small delay between batches to avoid overwhelming FCM
      if (i + batchSize < userDocs.length) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }

    console.log(
      `Token cleanup completed: ${totalUsers} users processed, ` +
      `${totalTokensChecked} tokens checked, ${totalTokensRemoved} tokens removed`
    );

    // Log summary statistics to Firestore for monitoring
    await admin.firestore().collection('system_metrics').add({
      type: 'token_cleanup',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      usersProcessed: totalUsers,
      tokensChecked: totalTokensChecked,
      tokensRemoved: totalTokensRemoved,
      removalRate: totalTokensChecked > 0 ? (totalTokensRemoved / totalTokensChecked) : 0,
    });

  } catch (error) {
    console.error("Error in systematic token cleanup:", error);
  }
});

/**
 * Clean up tokens for a single user
 */
async function cleanupUserTokens(
  userId: string, 
  userData: any
): Promise<{checked: number, removed: number}> {
  const fcmTokens = userData.fcmTokens || [];
  let tokensChecked = 0;
  let tokensRemoved = 0;

  console.log(`Cleaning tokens for user ${userId}: ${fcmTokens.length} tokens`);

  for (const tokenData of fcmTokens) {
    if (typeof tokenData === "object" && tokenData.token) {
      tokensChecked++;
      
      // Check token age (remove if older than 9 months)
      const tokenAge = Date.now() - new Date(tokenData.createdAt).getTime();
      const maxAge = 270 * 24 * 60 * 60 * 1000; // 270 days in ms
      
      if (tokenAge > maxAge) {
        console.log(`Removing old token for user ${userId} (age: ${Math.floor(tokenAge / (24 * 60 * 60 * 1000))} days)`);
        await removeTokenFromUser(userId, tokenData.token);
        tokensRemoved++;
        continue;
      }

      // Test token validity with a dry-run message
      const isValid = await testTokenValidity(tokenData.token);
      if (!isValid) {
        console.log(`Removing invalid token for user ${userId}`);
        await removeTokenFromUser(userId, tokenData.token);
        tokensRemoved++;
      }
    }
  }

  return {checked: tokensChecked, removed: tokensRemoved};
}

/**
 * Test if an FCM token is still valid using a dry-run message
 */
async function testTokenValidity(token: string): Promise<boolean> {
  try {
    // Send a dry-run message (not delivered, just validates token)
    await admin.messaging().send({
      token: token,
      notification: {
        title: "Test",
        body: "Token validation test"
      },
      android: {
        priority: "high",
      },
      apns: {
        payload: {
          aps: {
            alert: "Token validation test",
          }
        }
      }
    }, true); // dry-run = true

    return true; // Token is valid
  } catch (error: any) {
    // Check for specific FCM error codes that indicate invalid tokens
    if (error.code === 'messaging/invalid-registration-token' ||
        error.code === 'messaging/registration-token-not-registered') {
      return false; // Token is invalid
    }
    
    // For other errors (network issues, etc.), assume token is valid
    console.log(`Unexpected error testing token: ${error.code || error.message}`);
    return true;
  }
}