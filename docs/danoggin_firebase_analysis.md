# Danoggin Firebase Integration Analysis

## Overview

Danoggin is a check-in monitoring application built on Flutter with a comprehensive Firebase backend. The system facilitates real-time monitoring between "responders" (main users) and "observers" (support partners) through scheduled check-ins, notifications, and relationship management.

## Firestore Database Structure

### Core Collections

#### 1. `users` Collection
The central user management collection storing all user profiles and settings.

**Document Structure:**
```typescript
{
  // Basic Profile
  name: string,
  role: "responder" | "observer",
  createdAt: Timestamp,
  
  // FCM Token Management
  fcmToken: string,                    // Latest token (convenience field)
  fcmTokenUpdatedAt: Timestamp,
  fcmTokens: [                         // Array of token objects
    {
      token: string,
      createdAt: string,
      platform: "ios" | "android",
      strikes?: number,                // Error tracking
      lastStrike?: {
        errorCode: string,
        timestamp: string,
        context: string
      }
    }
  ],
  
  // Badge Management (iOS)
  badgeCount: number,
  lastBadgeUpdate: Timestamp,
  
  // Responder-Specific Fields
  inviteCode?: string,                 // 6-character code for linking
  activeHours?: {
    startHour: string,                 // "08:00"
    endHour: string,                   // "20:00"
    timeZone: string,                  // "America/Detroit"
    updatedAt: Timestamp
  },
  checkInSettings?: {
    intervalMinutes: number,           // 5 (default)
    timeoutMinutes: number,            // 1 (default)
    enabled: boolean,
    nextCheckInTime: Timestamp,
    lastCheckInTime: Timestamp,
    lastUpdated: Timestamp
  },
  
  // Observer-Specific Fields
  inactivitySettings?: {
    thresholdHours: number,            // 24 (default)
    timeZone: string,
    updatedAt: Timestamp
  },
  
  // Relationship Management
  linkedObservers?: {                  // For responders
    [observerUid]: observerName
  },
  observing?: {                        // For observers
    [responderUid]: responderName
  },
  
  // Analytics & Engagement
  engagementMetrics?: {
    lastTokenFailure: Timestamp,
    tokenFailureCount: number,
    lastSuccessfulNotification: Timestamp,
    successfulNotificationCount: number,
    lastEngagementCheck: Timestamp,
    engagementScore: number,
    scoreUpdatedAt: Timestamp
  }
}
```

#### 2. `user_question_packs` Collection
Manages which question packs each user subscribes to.

**Document Structure:**
```typescript
{
  userId: string,
  subscribedPackIds: string[]
}
```

#### 3. `question_packs` Collection
Stores question content for check-ins.

**Document Structure:**
```typescript
{
  name: string,
  imageFolder?: string,              // Cloud storage reference
  questions: [
    {
      prompt: string,
      correctAnswer: {
        text?: string,
        imagePath?: string,
        imageUrl?: string
      },
      decoyAnswers: [
        // Same structure as correctAnswer
      ]
    }
  ]
}
```

#### 4. `responder_status` Collection
Tracks check-in history and real-time status.

**Document ID:** User UID
**Document Structure:**
```typescript
{
  createdAt: string,
  userId: string,
  lastActivity: string
}
```

**Subcollection:** `check_ins`
**Document ID:** ISO timestamp
```typescript
{
  timestamp: string,
  result: "correct" | "incorrect" | "missed" | "incorrect_first_attempt" | "missed_retry",
  prompt: string,
  responderId: string
}
```

### Analytics & Metrics Collections

#### 5. `user_engagement_events` Collection
Tracks user engagement events for business intelligence.

```typescript
{
  userId: string,
  eventType: "token_failure",
  tokenPrefix: string,               // First 12 chars for debugging
  errorCode: string,
  errorMessage: string,
  context: string,                   // "check_in_reminder", "observer_alert"
  timestamp: Timestamp,
  platform: "ios" | "android" | "unknown"
}
```

#### 6. `token_events` Collection
Real-time token health tracking (auto-generated IDs).

```typescript
{
  userId: string,
  userName: string,
  token: string,                     // Truncated for privacy
  eventType: "removal" | "error" | "strike",
  reason: string,
  details: any,
  context: string,
  timestamp: string
}
```

#### 7. `daily_metrics` Collection
Daily aggregated token health metrics.

**Document ID:** `token_metrics_YYYY-MM-DD`
```typescript
{
  date: string,                      // YYYY-MM-DD
  timestamp: Timestamp,
  tokenRemovals: {
    totalRemovals: number,
    removalReasons: {
      strike_threshold: number,
      age_limit: number,
      invalid_token: number,
      weekly_cleanup: number,
      other: number
    },
    affectedUsers: number,
    userDetails: [
      {
        userId: string,
        userName: string,
        reason: string,
        context: string,
        timestamp: string
      }
    ]
  },
  tokenErrors: {
    totalErrors: number,
    totalStrikes: number,
    errorTypes: {
      temporary_network: number,
      temporary_service: number,
      temporary_unknown: number,
      invalid_token: number,
      unregistered_token: number,
      mismatched_credential: number,
      other_definitive: number
    },
    affectedUsers: number,
    errorsByContext: {
      check_in_reminder: number,
      observer_alert: number,
      other: number
    }
  },
  userImpact: {
    usersWithTokenIssues: number,
    userDetails: [
      {
        userId: string,
        userName: string,
        userRole: string,
        totalStrikes: number,
        tokensWithIssues: number,
        totalTokens: number
      }
    ]
  },
  systemSummary: {
    totalActiveUsers: number,
    totalTokens: number,
    healthyTokens: number,
    tokensWithStrikes: number,
    oldTokens: number,
    tokenHealthPercentage: string
  }
}
```

#### 8. `system_metrics` Collection
System performance and cleanup statistics.

```typescript
{
  type: "token_cleanup",
  timestamp: Timestamp,
  usersProcessed: number,
  tokensChecked: number,
  tokensRemoved: number,
  removalRate: number
}
```

## Firebase Cloud Messaging (FCM) Integration

### Message Types and Triggers

#### 1. Check-in Reminders
**Trigger:** Scheduled function runs every 5 minutes
**Recipients:** Responders with due check-ins
**Payload:**
```typescript
{
  notification: {
    title: "Danoggin Check-In",
    body: "Time to answer a quick question!"
  },
  data: {
    type: "check_in_reminder",
    responderId: string,
    timestamp: string
  },
  apns: {
    payload: {
      aps: {
        sound: "default",
        badge: number,
        alert: { title, body }
      }
    }
  },
  android: {
    notification: {
      sound: "default",
      priority: "high",
      channelId: "danoggin_alerts"
    }
  }
}
```

#### 2. Observer Alerts
**Trigger:** Firestore trigger on new check-in documents with "missed" or "incorrect" results
**Recipients:** All linked observers of the responder
**Payload:**
```typescript
{
  notification: {
    title: "Danoggin Alert: [result] check-in",
    body: "[responderName] [result] a check-in at [time]"
  },
  data: {
    type: "check_in_alert",
    responderName: string,
    result: string,
    timestamp: string,
    checkInId: string
  }
}
```

#### 3. Badge Clearing
**Trigger:** Manual app actions or Cloud Function calls
**Purpose:** Clear iOS badge counts
**Payload:**
```typescript
{
  apns: {
    payload: {
      aps: {
        badge: 0,
        "content-available": 1  // Silent notification
      }
    }
  },
  android: {
    data: {
      badgeCount: "0"
    }
  }
}
```

### FCM Token Management

#### Token Storage Strategy
- **Multiple Tokens Per User:** Each device gets its own token stored in `fcmTokens` array
- **Platform Detection:** Inferred from token length (iOS typically longer)
- **Token Metadata:** Creation time, platform, error tracking

#### Token Health Monitoring
The system implements a sophisticated "strike system" for token health:

**Strike System Rules:**
1. **Definitive Errors = Strike:** Invalid token, unregistered token, credential mismatch
2. **Temporary Errors = No Strike:** Network issues, service unavailable
3. **Strike Threshold:** 3 strikes = token removal
4. **Forgiveness Policy:** Successful send resets all strikes
5. **Age Limit:** Tokens older than 270 days are removed during weekly cleanup

**Error Categorization:**
```typescript
// Definitive invalidity (causes strikes)
const definitivelyInvalidCodes = [
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered', 
  'messaging/mismatched-credential'
];

// Temporary issues (logged but no strikes)
// - Network timeouts
// - Service unavailable
// - Unknown errors
```

## Cloud Functions Architecture

### Scheduled Functions

#### 1. `sendScheduledCheckInReminders`
- **Schedule:** Every 5 minutes
- **Purpose:** Send check-in notifications to responders
- **Logic:**
  - Query responders with `checkInSettings.nextCheckInTime <= now`
  - Verify active hours compliance
  - Send FCM notifications
  - Update next check-in time
  - Handle token errors with strike system

#### 2. `cleanupInvalidTokens`
- **Schedule:** Weekly (Sunday 2 AM UTC)
- **Purpose:** Systematic token cleanup
- **Process:**
  - Check all users with FCM tokens
  - Remove tokens older than 270 days
  - Remove tokens with 2+ strikes
  - Dry-run test remaining tokens
  - Log cleanup statistics

#### 3. `processDailyTokenMetrics`
- **Schedule:** Daily (1 AM UTC)
- **Purpose:** Aggregate token health metrics
- **Output:** Daily metrics documents for monitoring trends
- **Cleanup:** Removes events older than 30 days, metrics older than 90 days

### Firestore Triggers

#### 1. `processCheckInResult`
- **Trigger:** New documents in `responder_status/{uid}/check_ins/{id}`
- **Conditions:** result is "missed" or "incorrect"
- **Actions:**
  - Fetch responder details
  - Find linked observers
  - Send FCM alerts to observers
  - Update badge counts

### HTTP Functions

#### 1. `testFCM`
- **Purpose:** Development testing of FCM delivery
- **CORS:** Enabled for web testing
- **Usage:** Accepts token and message, sends test notification

#### 2. `clearUserBadge`
- **Purpose:** Clear iOS badge counts for all user devices
- **Process:** Send silent notification with badge=0 to all user tokens

## Data Flow Patterns

### Check-in Workflow
1. **Scheduled Trigger:** Cloud Function identifies due check-ins
2. **FCM Delivery:** Notification sent to responder's devices
3. **App Response:** User answers question in Flutter app
4. **Firestore Write:** Result stored in `responder_status/check_ins`
5. **Observer Alert:** Trigger function notifies observers of issues
6. **Schedule Update:** Next check-in time calculated and stored

### Token Health Lifecycle
1. **Token Registration:** App saves FCM token to user document
2. **Strike Accumulation:** Failed deliveries add strikes
3. **Forgiveness:** Successful deliveries reset strikes
4. **Removal:** 3 strikes or weekly cleanup removes tokens
5. **Metrics Collection:** All events logged for analysis

### Relationship Management
1. **Invite Code Generation:** Responder gets 6-character code
2. **Observer Linking:** Observer enters code to establish relationship
3. **Bidirectional Updates:** Both user documents updated with relationship
4. **Alert Routing:** Failed check-ins sent to all linked observers

## Development vs Production Configurations

### Development Features
- **Ultra-fast Testing:** Minutes instead of hours for inactivity
- **Debug Logging:** Extensive FCM message tracking
- **Dev Mode Flags:** `kDevModeEnabled` throughout codebase
- **Manual Triggers:** Refresh buttons and test notifications

### Production Safeguards
- **Rate Limiting:** Batched processing to avoid FCM quota issues
- **Error Recovery:** Graceful degradation when services fail
- **Data Retention:** Automatic cleanup of old metrics and events
- **Privacy Protection:** Token prefixes only in logs

## Security Considerations

### Data Privacy
- **Token Storage:** Full tokens in secure Firestore, prefixes in logs
- **User Identification:** UIDs used instead of names in sensitive contexts
- **Anonymous Auth:** Firebase anonymous authentication for user sessions

### Access Patterns
- **User Isolation:** Security rules ensure users only access their data
- **Relationship Validation:** Bidirectional checks for observer-responder links
- **Cloud Function Security:** Server-side validation of all operations

## Monitoring and Analytics

### Real-time Metrics
- Token health tracking with strike system
- User engagement scoring
- Notification delivery success rates
- Check-in completion patterns

### Business Intelligence
- Daily aggregated metrics for trend analysis
- User behavior patterns and retention
- System performance monitoring
- Token lifecycle analytics

### Operational Monitoring
- FCM quota usage and error rates
- Firestore read/write patterns
- Cloud Function execution metrics
- Badge management effectiveness

This comprehensive Firebase integration provides robust real-time monitoring capabilities while maintaining detailed analytics for continuous improvement of the notification system.