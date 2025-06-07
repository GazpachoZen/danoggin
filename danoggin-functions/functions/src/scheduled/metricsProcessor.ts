import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

/**
 * Scheduled function to process and store FCM token metrics daily
 * Runs every day at 1 AM UTC to analyze token cleanup patterns
 */
export const processDailyTokenMetrics = onSchedule({
  schedule: "0 1 * * *", // Daily at 1 AM UTC
  timeZone: "UTC",
}, async () => {
  console.log("Starting daily FCM token metrics processing");

  try {
    const today = new Date();
    const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);
    
    // Generate date strings for queries and document IDs
    const todayStr = today.toISOString().split('T')[0]; // YYYY-MM-DD
    const yesterdayStr = yesterday.toISOString().split('T')[0];
    
    console.log(`Processing metrics for ${yesterdayStr}`);

    // Collect metrics from multiple sources
    const metrics = {
      date: yesterdayStr,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      tokenRemovals: await collectTokenRemovalMetrics(yesterdayStr),
      tokenErrors: await collectTokenErrorMetrics(yesterdayStr),
      userImpact: await collectUserImpactMetrics(yesterdayStr),
      systemSummary: await collectSystemSummary(yesterdayStr),
    };

    // Store the aggregated metrics
    await admin.firestore()
      .collection('daily_metrics')
      .doc(`token_metrics_${yesterdayStr}`)
      .set(metrics);

console.log(`Daily token metrics processed and stored for ${yesterdayStr}`);

    // Clean up old data to prevent storage bloat
    await cleanupOldMetrics();        // Keep 90 days of daily metrics
    await cleanupOldTokenEvents();    // Keep 30 days of raw token events
    
  } catch (error) {
    console.error("Error processing daily token metrics:", error);
  }
});

/**
 * Collect token removal statistics from real event data
 */
async function collectTokenRemovalMetrics(dateStr: string): Promise<any> {
  try {
    // Calculate date range for yesterday's events
    const startDate = new Date(`${dateStr}T00:00:00.000Z`);
    const endDate = new Date(`${dateStr}T23:59:59.999Z`);
    
    // Query token removal events from yesterday
    const removalEvents = await admin.firestore()
      .collection('token_events')
      .where('eventType', '==', 'removal')
      .where('timestamp', '>=', startDate.toISOString())
      .where('timestamp', '<=', endDate.toISOString())
      .get();

    const removalStats = {
      totalRemovals: removalEvents.size,
      removalReasons: {
        strike_threshold: 0,
        age_limit: 0,
        invalid_token: 0,
        weekly_cleanup: 0,
        other: 0,
      },
      affectedUsers: new Set(),
      userDetails: [] as any[],
    };

    // Process each removal event
    removalEvents.docs.forEach(doc => {
      const eventData = doc.data();
      const reason = eventData.reason || 'other';
      const userId = eventData.userId;
      const userName = eventData.userName || 'Unknown User';
      
      // Count by reason
      if (removalStats.removalReasons.hasOwnProperty(reason)) {
        (removalStats.removalReasons as any)[reason]++;
      } else {
        removalStats.removalReasons.other++;
      }
      
      // Track affected users
      removalStats.affectedUsers.add(userId);
      
      // Store user details for analysis
      removalStats.userDetails.push({
        userId: userId,
        userName: userName,
        reason: reason,
        context: eventData.context,
        timestamp: eventData.timestamp,
        details: eventData.details,
      });
    });

    // Convert Set to count
    const finalStats = {
      ...removalStats,
      affectedUsers: removalStats.affectedUsers.size,
      userDetails: removalStats.userDetails.sort((a, b) => 
        new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
      ),
    };

    console.log(`Token removal metrics collected for ${dateStr}: ${finalStats.totalRemovals} removals affecting ${finalStats.affectedUsers} users`);
    return finalStats;

  } catch (error: any) {
    console.error(`Error collecting token removal metrics for ${dateStr}:`, error);
    return {
      totalRemovals: 0,
      removalReasons: {},
      affectedUsers: 0,
      userDetails: [],
      error: error?.toString() || 'Unknown error',
    };
  }
}

/**
 * Collect token error patterns from real event data
 */
async function collectTokenErrorMetrics(dateStr: string): Promise<any> {
  try {
    // Calculate date range for yesterday's events
    const startDate = new Date(`${dateStr}T00:00:00.000Z`);
    const endDate = new Date(`${dateStr}T23:59:59.999Z`);
    
    // Query both error and strike events from yesterday
    const errorEvents = await admin.firestore()
      .collection('token_events')
      .where('eventType', 'in', ['error', 'strike'])
      .where('timestamp', '>=', startDate.toISOString())
      .where('timestamp', '<=', endDate.toISOString())
      .get();

    const errorStats = {
      totalErrors: 0,
      totalStrikes: 0,
      errorTypes: {
        // Temporary errors (no strikes applied)
        temporary_network: 0,
        temporary_service: 0,
        temporary_unknown: 0,
        // Definitive errors (strikes applied)
        invalid_token: 0,
        unregistered_token: 0,
        mismatched_credential: 0,
        other_definitive: 0,
      },
      affectedUsers: new Set(),
      errorsByContext: {
        check_in_reminder: 0,
        observer_alert: 0,
        other: 0,
      },
      userDetails: [] as any[],
    };

    // Process each error/strike event
    errorEvents.docs.forEach(doc => {
      const eventData = doc.data();
      const eventType = eventData.eventType;
      const reason = eventData.reason || 'unknown';
      const userId = eventData.userId;
      const userName = eventData.userName || 'Unknown User';
      const context = eventData.context || 'other';
      
      if (eventType === 'error') {
        errorStats.totalErrors++;
        
        // Categorize temporary errors
        if (reason.includes('network') || reason.includes('unavailable')) {
          errorStats.errorTypes.temporary_network++;
        } else if (reason.includes('service') || reason.includes('server')) {
          errorStats.errorTypes.temporary_service++;
        } else {
          errorStats.errorTypes.temporary_unknown++;
        }
      } else if (eventType === 'strike') {
        errorStats.totalStrikes++;
        
        // Categorize definitive errors that caused strikes
        if (reason === 'messaging/invalid-registration-token') {
          errorStats.errorTypes.invalid_token++;
        } else if (reason === 'messaging/registration-token-not-registered') {
          errorStats.errorTypes.unregistered_token++;
        } else if (reason === 'messaging/mismatched-credential') {
          errorStats.errorTypes.mismatched_credential++;
        } else {
          errorStats.errorTypes.other_definitive++;
        }
      }
      
      // Track by context
      if (errorStats.errorsByContext.hasOwnProperty(context)) {
        (errorStats.errorsByContext as any)[context]++;
      } else {
        errorStats.errorsByContext.other++;
      }
      
      // Track affected users
      errorStats.affectedUsers.add(userId);
      
      // Store user details for analysis
      errorStats.userDetails.push({
        userId: userId,
        userName: userName,
        eventType: eventType,
        reason: reason,
        context: context,
        timestamp: eventData.timestamp,
        details: eventData.details,
      });
    });

    // Convert Set to count and finalize stats
    const finalStats = {
      ...errorStats,
      affectedUsers: errorStats.affectedUsers.size,
      totalEvents: errorStats.totalErrors + errorStats.totalStrikes,
      userDetails: errorStats.userDetails.sort((a, b) => 
        new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
      ),
    };

    console.log(
      `Token error metrics collected for ${dateStr}: ` +
      `${finalStats.totalErrors} temporary errors, ${finalStats.totalStrikes} strikes affecting ${finalStats.affectedUsers} users`
    );
    return finalStats;

  } catch (error: any) {
    console.error(`Error collecting token error metrics for ${dateStr}:`, error);
    return {
      totalErrors: 0,
      totalStrikes: 0,
      errorTypes: {},
      affectedUsers: 0,
      errorsByContext: {},
      userDetails: [],
      error: error?.toString() || 'Unknown error',
    };
  }
}

/**
 * Collect user impact statistics with user names
 */
async function collectUserImpactMetrics(dateStr: string): Promise<any> {
  try {
    // Get users who have tokens with strikes or recent issues
    const usersWithIssues: any[] = [];
    
    const usersSnapshot = await admin.firestore()
      .collection('users')
      .where('fcmTokens', '!=', [])
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const fcmTokens = userData.fcmTokens || [];
      const userName = userData.name || 'Unknown User';
      
      let userHasIssues = false;
      let totalStrikes = 0;
      let tokensWithIssues = 0;
      
      for (const tokenData of fcmTokens) {
        if (typeof tokenData === "object" && tokenData.strikes && tokenData.strikes > 0) {
          userHasIssues = true;
          totalStrikes += tokenData.strikes;
          tokensWithIssues++;
        }
      }
      
      if (userHasIssues) {
        usersWithIssues.push({
          userId: userDoc.id,
          userName: userName,
          userRole: userData.role || 'unknown',
          totalStrikes: totalStrikes,
          tokensWithIssues: tokensWithIssues,
          totalTokens: fcmTokens.length,
        });
      }
    }

    return {
      usersWithTokenIssues: usersWithIssues.length,
      userDetails: usersWithIssues.sort((a, b) => b.totalStrikes - a.totalStrikes), // Sort by most strikes
      totalUsersAnalyzed: usersSnapshot.size,
    };

} catch (error: any) {
    console.error("Error collecting user impact metrics:", error);
    return {
      usersWithTokenIssues: 0,
      userDetails: [],
      totalUsersAnalyzed: 0,
      error: error?.toString() || 'Unknown error',
    };
  }
}

/**
 * Collect system-wide summary statistics
 */
async function collectSystemSummary(dateStr: string): Promise<any> {
  try {
    // Get overall token health statistics
    const usersSnapshot = await admin.firestore()
      .collection('users')
      .where('fcmTokens', '!=', [])
      .get();

    let totalTokens = 0;
    let healthyTokens = 0;
    let tokensWithStrikes = 0;
    let oldTokens = 0;
    
    const maxAge = 270 * 24 * 60 * 60 * 1000; // 270 days in ms
    const now = Date.now();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const fcmTokens = userData.fcmTokens || [];
      
      for (const tokenData of fcmTokens) {
        if (typeof tokenData === "object" && tokenData.token) {
          totalTokens++;
          
          const strikes = tokenData.strikes || 0;
          if (strikes > 0) {
            tokensWithStrikes++;
          } else {
            healthyTokens++;
          }
          
          if (tokenData.createdAt) {
            const tokenAge = now - new Date(tokenData.createdAt).getTime();
            if (tokenAge > maxAge) {
              oldTokens++;
            }
          }
        }
      }
    }

    return {
      totalActiveUsers: usersSnapshot.size,
      totalTokens: totalTokens,
      healthyTokens: healthyTokens,
      tokensWithStrikes: tokensWithStrikes,
      oldTokens: oldTokens,
      tokenHealthPercentage: totalTokens > 0 ? (healthyTokens / totalTokens * 100).toFixed(1) : 0,
    };

} catch (error: any) {
    console.error("Error collecting system summary:", error);
    return {
      totalActiveUsers: 0,
      totalTokens: 0,
      error: error?.toString() || 'Unknown error',
    };
  }
}

/**
 * Clean up metrics older than 90 days
 */
async function cleanupOldMetrics(): Promise<void> {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 90);
    const cutoffStr = cutoffDate.toISOString().split('T')[0];
    
    const oldMetricsQuery = await admin.firestore()
      .collection('daily_metrics')
      .where('date', '<', cutoffStr)
      .get();

    if (!oldMetricsQuery.empty) {
      const batch = admin.firestore().batch();
      oldMetricsQuery.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      
      console.log(`Cleaned up ${oldMetricsQuery.size} old metric documents`);
    }

} catch (error: any) {
    console.error("Error cleaning up old metrics:", error);
  }
}

/**
 * Clean up token events older than 30 days to prevent collection growth
 */
async function cleanupOldTokenEvents(): Promise<void> {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 30);
    const cutoffStr = cutoffDate.toISOString();
    
    console.log(`Cleaning up token events older than ${cutoffStr}`);
    
    // Query old events in batches to avoid memory issues
    const batchSize = 500;
    let totalDeleted = 0;
    
    while (true) {
      const oldEventsQuery = await admin.firestore()
        .collection('token_events')
        .where('timestamp', '<', cutoffStr)
        .limit(batchSize)
        .get();

      if (oldEventsQuery.empty) {
        break; // No more old events to delete
      }

      // Delete in batches
      const batch = admin.firestore().batch();
      oldEventsQuery.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      
      totalDeleted += oldEventsQuery.size;
      console.log(`Deleted ${oldEventsQuery.size} old token events (total: ${totalDeleted})`);
      
      // If we got less than the batch size, we're done
      if (oldEventsQuery.size < batchSize) {
        break;
      }
      
      // Small delay to avoid overwhelming Firestore
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    if (totalDeleted > 0) {
      console.log(`Token events cleanup completed: ${totalDeleted} old events removed`);
    } else {
      console.log('No old token events found to clean up');
    }

  } catch (error: any) {
    console.error("Error cleaning up old token events:", error);
  }
}
