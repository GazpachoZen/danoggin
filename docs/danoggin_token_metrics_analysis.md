# Danoggin FCM Token Health Metrics: Comprehensive Analysis

## Overview

Danoggin implements a sophisticated Firebase Cloud Messaging (FCM) token health monitoring system designed to track the reliability and validity of push notification delivery. This system is critical for ensuring that safety alerts reach their intended recipients, as failed notifications could have serious consequences in emergency situations.

## Token Health Metrics Architecture

### Real-Time Event Tracking

#### `token_events` Collection
The system maintains a real-time event log of all token-related activities:

```typescript
{
  userId: string,           // User who owns the token
  userName: string,         // For easier debugging and analytics
  token: string,           // Truncated to first 10 chars for privacy
  eventType: "removal" | "error" | "strike",
  reason: string,          // Specific error code or removal reason
  details: any,            // Additional context and metadata
  context: string,         // "check_in_reminder", "observer_alert", etc.
  timestamp: string        // ISO timestamp of the event
}
```

**Event Types:**
- **`error`**: Temporary delivery failures that don't count as strikes
- **`strike`**: Definitive token invalidity that counts toward removal
- **`removal`**: Token actually removed from user's account

### Aggregated Daily Metrics

#### `daily_metrics` Collection
Every day at 1 AM UTC, the system processes the raw events into comprehensive daily reports:

```typescript
{
  date: "YYYY-MM-DD",
  timestamp: Timestamp,
  
  // Token Removal Analysis
  tokenRemovals: {
    totalRemovals: number,
    removalReasons: {
      strike_threshold: number,    // Removed after 3 strikes
      age_limit: number,          // Removed after 270 days
      invalid_token: number,      // Immediately invalid
      weekly_cleanup: number,     // Systematic cleanup
      other: number
    },
    affectedUsers: number,        // Unique users who lost tokens
    userDetails: [               // Detailed breakdown per user
      {
        userId: string,
        userName: string,
        reason: string,
        context: string,
        timestamp: string
      }
    ]
  },
  
  // Error Pattern Analysis
  tokenErrors: {
    totalErrors: number,          // Temporary errors (no strikes)
    totalStrikes: number,         // Definitive errors (with strikes)
    errorTypes: {
      // Temporary errors (no strikes applied)
      temporary_network: number,
      temporary_service: number,
      temporary_unknown: number,
      // Definitive errors (strikes applied)
      invalid_token: number,
      unregistered_token: number,
      mismatched_credential: number,
      other_definitive: number
    },
    affectedUsers: number,
    errorsByContext: {
      check_in_reminder: number,  // Errors during responder notifications
      observer_alert: number,     // Errors during observer alerts
      other: number
    }
  },
  
  // User Impact Assessment
  userImpact: {
    usersWithTokenIssues: number,
    userDetails: [
      {
        userId: string,
        userName: string,
        userRole: "responder" | "observer",
        totalStrikes: number,
        tokensWithIssues: number,
        totalTokens: number
      }
    ]
  },
  
  // System-Wide Health Summary
  systemSummary: {
    totalActiveUsers: number,
    totalTokens: number,
    healthyTokens: number,        // Tokens with 0 strikes
    tokensWithStrikes: number,
    oldTokens: number,           // Tokens > 270 days old
    tokenHealthPercentage: string // Overall health percentage
  }
}
```

### User-Level Token Storage

#### Token Metadata in `users` Collection
Each user's FCM tokens are stored with comprehensive metadata:

```typescript
{
  fcmTokens: [
    {
      token: string,              // Full FCM token
      createdAt: string,          // When token was first registered
      platform: "ios" | "android", // Detected platform
      strikes?: number,           // Current strike count (0-2, removed at 3)
      lastStrike?: {
        errorCode: string,        // Last error that caused a strike
        timestamp: string,        // When the strike occurred
        context: string          // What notification caused the strike
      }
    }
  ],
  
  // Additional engagement metrics
  engagementMetrics?: {
    lastTokenFailure: Timestamp,
    tokenFailureCount: number,
    lastSuccessfulNotification: Timestamp,
    successfulNotificationCount: number,
    engagementScore: number     // 0-100 calculated score
  }
}
```

## Token Lifecycle and Health Management

### The Strike System

#### Strike Application Logic
```typescript
// Definitive errors that result in strikes
const definitivelyInvalidCodes = [
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/mismatched-credential'
];

// Temporary errors that are logged but don't cause strikes
// - Network timeouts
// - Service unavailable errors
// - Unknown/unclassified errors
```

#### Strike Progression
1. **First Strike (0→1)**: Token marked with strike, delivery continues
2. **Second Strike (1→2)**: Token flagged for removal during weekly cleanup
3. **Third Strike (2→3)**: Token immediately removed from user account

#### Forgiveness Policy
- **Successful Delivery**: All strikes reset to 0 ("all is forgiven")
- **Strike Reset**: Removes both `strikes` count and `lastStrike` metadata
- **Fresh Start**: Token treated as healthy after successful delivery

### Token Removal Triggers

#### Immediate Removal
- **Third Strike**: Automatic removal when strike threshold reached
- **Invalid During Cleanup**: Weekly dry-run test fails with definitive error

#### Scheduled Removal
- **Age Limit**: Tokens older than 270 days removed during weekly cleanup
- **Strike Threshold**: Tokens with 2+ strikes removed during weekly cleanup
- **Dry-run Failures**: Tokens that fail validation during systematic testing

### Weekly Cleanup Process

#### Systematic Token Validation
Every Sunday at 2 AM UTC, the system performs comprehensive token cleanup:

1. **Age Check**: Remove tokens older than 270 days
2. **Strike Check**: Remove tokens with 2+ accumulated strikes
3. **Dry-run Validation**: Test remaining tokens with FCM dry-run API
4. **Batch Processing**: Process users in batches of 50 to avoid overwhelming FCM
5. **Metrics Collection**: Log all cleanup activities for analysis

## Metrics Coverage Analysis

### What the Metrics Cover Well

#### ✅ Definitive Token Invalidity
- **Invalid Registration Tokens**: Tokens that no longer exist in FCM
- **Unregistered Tokens**: Tokens for uninstalled apps (after FCM timeout)
- **Credential Mismatches**: Tokens from wrong Firebase project
- **Age-based Expiration**: Tokens that have exceeded reasonable lifetime

#### ✅ Delivery Failure Patterns
- **Temporal Patterns**: When failures occur (check-ins vs alerts)
- **User Impact**: Which users are affected by delivery issues
- **Error Classification**: Distinguishing temporary vs permanent failures
- **Success Rate Tracking**: Overall notification delivery success rates

#### ✅ System Health Monitoring
- **Fleet Health**: Percentage of healthy tokens across all users
- **User Distribution**: How many users have problematic tokens
- **Cleanup Effectiveness**: Impact of systematic token maintenance
- **Trend Analysis**: Daily aggregation enables trend identification

### Edge Cases and Limitations

#### ❌ App Uninstallation Detection

**The Challenge:**
When a user uninstalls Danoggin, their FCM token becomes invalid, but this isn't immediately detectable.

**Current Coverage:**
- **Delayed Detection**: FCM doesn't immediately invalidate tokens for uninstalled apps
- **Grace Period**: Tokens may remain "valid" for hours or days after uninstall
- **Eventual Detection**: Token will eventually be marked as `messaging/registration-token-not-registered`
- **Cleanup Delay**: Could take up to a week (until next cleanup cycle) to be removed

**Metrics Impact:**
```typescript
// What we can measure:
tokenErrors: {
  errorTypes: {
    unregistered_token: number  // Eventually catches uninstalls
  }
}

// What we miss:
// - Immediate uninstall detection
// - Time between uninstall and detection
// - Failed notifications during grace period
```

#### ❌ Extended Device Offline Periods

**The Challenge:**
When a device is off or offline for extended periods, notifications queue in FCM but we can't distinguish this from token invalidity.

**Current Coverage:**
- **No Immediate Detection**: Offline devices don't generate error responses
- **Timeout Behavior**: FCM eventually expires queued messages (typically 4 weeks)
- **False Negatives**: Offline appears healthy until timeout expires
- **Delayed Failure**: Only detected when FCM gives up on delivery

**Metrics Impact:**
```typescript
// What we can measure:
tokenErrors: {
  errorTypes: {
    temporary_network: number  // Some network-related timeouts
  }
}

// What we miss:
// - Device offline status
// - Queue depth in FCM
// - Expected vs actual delivery timing
// - User accessibility during offline periods
```

#### ❌ Platform-Specific Notification Settings

**The Challenge:**
Users can disable notifications at the OS level without affecting token validity.

**Current Coverage:**
- **Token Remains Valid**: FCM token stays registered even if notifications disabled
- **Silent Failures**: Notifications "succeed" from FCM perspective but aren't shown
- **No Error Response**: OS-level blocking doesn't generate FCM errors
- **Invisible Problem**: Metrics show success while user receives nothing

**Metrics Gap:**
```typescript
// What we measure:
systemSummary: {
  tokenHealthPercentage: "95%"  // Misleadingly high
}

// What we don't measure:
// - OS-level notification permissions
// - Do Not Disturb settings
// - App-specific notification settings
// - Actual user notification receipt
```

#### ❌ Network-Related Delivery Delays

**The Challenge:**
Poor network conditions can cause significant delivery delays without generating errors.

**Current Coverage:**
- **Success Measurement**: Only tracks eventual delivery, not timing
- **No Latency Metrics**: No measurement of notification delivery speed
- **Binary Success**: Either delivered or failed, no partial success states
- **Context Missing**: No correlation between network conditions and delivery

#### ❌ Multiple Device Scenarios

**The Challenge:**
Users with multiple devices create complex token health scenarios.

**Current Coverage:**
- **Per-Token Tracking**: Each device token tracked independently
- **No Cross-Device Correlation**: No understanding of user's total device fleet
- **Partial Failure Blindness**: If one device works, overall user appears healthy
- **Device Lifecycle**: No tracking of device replacement patterns

**Metrics Limitations:**
```typescript
// Per-user view:
userImpact: {
  userDetails: [
    {
      totalTokens: 3,          // 3 devices
      tokensWithIssues: 1,     // 1 problematic device
      // But no visibility into:
      // - Which device is primary
      // - User's device usage patterns
      // - Cross-device notification redundancy
    }
  ]
}
```

## Critical Scenarios Analysis

### Scenario 1: Silent App Uninstall

**Timeline:**
1. **T+0**: User uninstalls Danoggin
2. **T+1 hour**: Check-in reminder sent, appears successful
3. **T+6 hours**: Observer alert sent, appears successful
4. **T+24-72 hours**: FCM marks token as unregistered
5. **T+1 week**: Weekly cleanup removes token

**Metrics Blindness:**
- Up to 1 week of false confidence in notification delivery
- Failed safety notifications with no error indication
- User appears active in system while completely unreachable

### Scenario 2: Extended Phone Power-Off

**Timeline:**
1. **T+0**: Phone battery dies or device powered off
2. **T+1-27 days**: Notifications queue in FCM, appear successful
3. **T+28 days**: FCM expires queued messages
4. **T+28+ days**: New notifications start failing with timeout errors

**Metrics Blindness:**
- Nearly a month of queued notifications appearing as successful
- No distinction between "delivered to device" and "device accessible"
- Emergency situations could persist undetected for weeks

### Scenario 3: Notification Permission Revocation

**Timeline:**
1. **T+0**: User disables notifications for Danoggin at OS level
2. **T+ongoing**: All notifications continue to "succeed" from FCM perspective
3. **T+indefinite**: User never receives notifications but appears healthy

**Metrics Blindness:**
- Permanent invisible failure mode
- No detection mechanism exists
- Safety system completely compromised while appearing functional

## Recommendations for Improved Coverage

### Enhanced Detection Mechanisms

#### Application Heartbeat System
```typescript
// Periodic app heartbeat to detect uninstalls/offline status
{
  userId: string,
  lastAppHeartbeat: Timestamp,
  heartbeatMissedCount: number,
  deviceOnlineStatus: "online" | "offline" | "unknown"
}
```

#### Delivery Confirmation Tracking
```typescript
// Track notification receipt confirmation
{
  notificationId: string,
  sentAt: Timestamp,
  deliveredAt?: Timestamp,
  acknowledgedAt?: Timestamp,
  deliveryLatency?: number
}
```

#### Platform Permission Monitoring
```typescript
// Monitor OS-level notification permissions
{
  userId: string,
  notificationPermissions: {
    granted: boolean,
    requestedAt: Timestamp,
    deniedAt?: Timestamp,
    platform: "ios" | "android"
  }
}
```

### Improved Metrics

#### Real-Time Health Scoring
```typescript
{
  userId: string,
  realtimeHealthScore: {
    score: number,              // 0-100
    factors: {
      tokenValidity: number,    // Based on recent FCM success
      appActivity: number,      // Based on heartbeat
      deliveryLatency: number,  // Based on confirmation timing
      permissionStatus: number  // Based on OS permissions
    },
    lastUpdated: Timestamp
  }
}
```

#### Notification Journey Tracking
```typescript
{
  notificationId: string,
  journey: [
    { stage: "queued", timestamp: Timestamp },
    { stage: "sent_to_fcm", timestamp: Timestamp },
    { stage: "delivered_to_device", timestamp: Timestamp },
    { stage: "displayed_to_user", timestamp: Timestamp },
    { stage: "acknowledged_by_user", timestamp: Timestamp }
  ],
  failurePoint?: string,
  totalLatency?: number
}
```

## Conclusion

Danoggin's current FCM token health metrics provide excellent coverage for traditional notification delivery failures and token lifecycle management. The strike system effectively manages transient errors while the daily aggregation enables trend analysis and system health monitoring.

However, significant blind spots exist around:
- **Immediate uninstall detection** (up to 1 week delay)
- **Extended offline periods** (up to 4 weeks of false positives)
- **OS-level notification blocking** (permanent invisible failures)
- **Delivery timing and latency** (binary success without performance metrics)

For a safety-critical application like Danoggin, these limitations could result in dangerous false confidence in notification delivery. The system would benefit from enhanced real-time detection mechanisms and more comprehensive delivery confirmation tracking to ensure truly reliable safety monitoring.