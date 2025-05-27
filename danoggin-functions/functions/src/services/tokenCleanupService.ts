import * as admin from "firebase-admin";

/**
 * Remove a specific FCM token from a user's Firestore document
 */
export async function removeTokenFromUser(
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

/**
 * Remove an invalid FCM token from a user's document (legacy function)
 */
export async function removeInvalidToken(
  userId: string,
  invalidToken: string
): Promise<void> {
  return removeTokenFromUser(userId, invalidToken);
}