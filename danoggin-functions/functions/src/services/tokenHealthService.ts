import * as admin from "firebase-admin";

/**
 * Log token failure events for analytics and business intelligence
 */
export async function logTokenFailureForAnalytics(
  userId: string,
  token: string,
  error: any,
  context: string
): Promise<void> {
  try {
    // Log the failure event for analytics
    await admin.firestore().collection('user_engagement_events').add({
      userId: userId,
      eventType: 'token_failure',
      tokenPrefix: token.substring(0, 12), // For debugging, not full token
      errorCode: error.code || 'unknown',
      errorMessage: error.message || 'Unknown error',
      context: context, // "check_in_reminder", "observer_alert", etc.
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      platform: detectPlatform(token),
    });

    // Update user-level engagement metrics
    await admin.firestore().collection('users').doc(userId).update({
      'engagementMetrics.lastTokenFailure': admin.firestore.FieldValue.serverTimestamp(),
      'engagementMetrics.tokenFailureCount': admin.firestore.FieldValue.increment(1),
      'engagementMetrics.lastEngagementCheck': admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Logged token failure analytics for user ${userId}`);
  } catch (analyticsError) {
    // Don't let analytics logging break the main flow
    console.error('Error logging token failure analytics:', analyticsError);
  }
}

/**
 * Log successful token usage for engagement tracking
 */
export async function logTokenSuccess(
  userId: string,
  context: string
): Promise<void> {
  try {
    await admin.firestore().collection('users').doc(userId).update({
      'engagementMetrics.lastSuccessfulNotification': admin.firestore.FieldValue.serverTimestamp(),
      'engagementMetrics.successfulNotificationCount': admin.firestore.FieldValue.increment(1),
      'engagementMetrics.lastEngagementCheck': admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Error logging token success:', error);
  }
}

/**
 * Detect platform from FCM token characteristics
 */
function detectPlatform(token: string): string {
  // This is a rough heuristic - FCM tokens don't explicitly contain platform info
  // iOS tokens tend to be longer and have different character patterns
  if (token.length > 150) {
    return 'ios';
  } else if (token.length > 100) {
    return 'android';
  }
  return 'unknown';
}

/**
 * Update user engagement score based on recent activity
 */
export async function updateEngagementScore(userId: string): Promise<void> {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const metrics = userData?.engagementMetrics || {};

    // Calculate engagement score based on recent activity
    const now = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;

    let score = 100; // Start with perfect score

    // Reduce score for token failures
    const failureCount = metrics.tokenFailureCount || 0;
    score -= Math.min(failureCount * 10, 50); // Max 50 point reduction

    // Reduce score for time since last successful notification
    const lastSuccess = metrics.lastSuccessfulNotification?.toDate?.()?.getTime();
    if (lastSuccess) {
      const daysSinceSuccess = (now - lastSuccess) / dayMs;
      if (daysSinceSuccess > 7) {
        score -= Math.min((daysSinceSuccess - 7) * 5, 30); // Max 30 point reduction
      }
    }

    // Ensure score doesn't go below 0
    score = Math.max(0, score);

    await admin.firestore().collection('users').doc(userId).update({
      'engagementMetrics.engagementScore': score,
      'engagementMetrics.scoreUpdatedAt': admin.firestore.FieldValue.serverTimestamp(),
    });

  } catch (error) {
    console.error('Error updating engagement score:', error);
  }
}