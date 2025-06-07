import {handleTokenError} from "../services/fcmService";
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
      
      // 1. Check token age (remove if older than 9 months)
      const tokenAge = Date.now() - new Date(tokenData.createdAt).getTime();
      const maxAge = 270 * 24 * 60 * 60 * 1000; // 270 days in ms
      
      if (tokenAge > maxAge) {
        console.log(`Removing old token for user ${userId} (age: ${Math.floor(tokenAge / (24 * 60 * 60 * 1000))} days)`);
        await removeTokenFromUser(userId, tokenData.token);
        tokensRemoved++;
        continue;
      }

      // 2. Check for accumulated strikes (remove if 2+ strikes during weekly cleanup)
      const strikes = tokenData.strikes || 0;
      if (strikes >= 2) {
        console.log(`Removing token with ${strikes} strikes for user ${userId}`);
        await removeTokenFromUser(userId, tokenData.token);
        tokensRemoved++;
        continue;
      }

      // 3. Test token validity with intelligent error handling
      const {shouldRemove, reason} = await shouldRemoveToken(userId, tokenData.token);
      if (shouldRemove) {
        console.log(`Removing invalid token for user ${userId}: ${reason}`);
        await removeTokenFromUser(userId, tokenData.token);
        tokensRemoved++;
      } else {
        console.log(`Keeping token for user ${userId}: ${reason}`);
      }
    }
  }

  return {checked: tokensChecked, removed: tokensRemoved};
}

/**
 * Test if an FCM token should be removed during cleanup
 * Uses same intelligent error categorization as real-time cleanup
 */
async function shouldRemoveToken(userId: string, token: string): Promise<{shouldRemove: boolean, reason: string}> {
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

    return {shouldRemove: false, reason: "token_valid"}; // Token is valid
  } catch (error: any) {
    const errorCode = error?.code || 'unknown';
    
    // Use same error categorization as real-time cleanup
    const definitivelyInvalidCodes = [
      'messaging/invalid-registration-token',
      'messaging/registration-token-not-registered',
      'messaging/mismatched-credential'
    ];
    
    if (definitivelyInvalidCodes.includes(errorCode)) {
      console.log(`Token definitely invalid during cleanup: ${errorCode}`);
      return {shouldRemove: true, reason: errorCode};
    }
    
    // For other errors (network issues, etc.), keep the token
    console.log(`Temporary error during token validation (keeping token): ${errorCode}`);
    return {shouldRemove: false, reason: `temporary_error_${errorCode}`};
  }
}