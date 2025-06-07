# FCM Token Management Enhancement Summary

## Overview
This document summarizes the comprehensive improvements made to the Danoggin project's FCM (Firebase Cloud Messaging) token management system. The enhancements move from aggressive immediate token removal to an intelligent strike-based system with comprehensive metrics tracking.

## Key Problems Addressed

### Original Issues
- **Aggressive Token Removal**: Any FCM send failure immediately removed tokens
- **No Resilience**: Temporary connectivity issues (airplane mode, poor signal) caused permanent token loss
- **No Visibility**: No metrics on why tokens were removed or which users were affected
- **Edge Case Failures**: Users going offline temporarily lost notification capability permanently

### Flight Scenario Example
- **Before**: User on 6-hour flight → First failed notification → Token removed → No notifications ever again
- **After**: User on 6-hour flight → Failed notifications logged as temporary → Token preserved → Notifications resume when back online

## Changes Made

### 1. Intelligent Strike System (`fcmService.ts`)

**Strike Policy:**
- Only definitive token invalidity errors count as strikes
- 3 strikes before token removal
- "All is forgiven" - successful sends reset all strikes

**Error Categorization:**
```typescript
// Definitive invalidity (causes strikes)
'messaging/invalid-registration-token'
'messaging/registration-token-not-registered' 
'messaging/mismatched-credential'

// Temporary issues (logged only, no strikes)
Network timeouts, server unavailable, rate limiting, etc.
```

**New Functions Added:**
- `handleTokenError()` - Intelligent error categorization
- `applyTokenStrike()` - Strike tracking and removal
- `resetTokenStrikes()` - Strike forgiveness on success
- `logTemporaryTokenError()` - Metrics without penalties
- `logTokenRemoval()` - Enhanced removal tracking

### 2. Real-time Event Collection (`fcmService.ts`)

**In-Memory Batching:**
- Events collected during Cloud Function execution
- Automatic flush at 100 events or function end
- Prevents memory bloat while ensuring data capture

**Event Types Tracked:**
```typescript
interface TokenEvent {
  userId: string;
  userName?: string;         // User name for analysis
  token: string;            // Token prefix only (privacy)
  eventType: 'removal' | 'error' | 'strike';
  reason: string;           // Specific error code or reason
  details: any;             // Additional context
  context: string;          // 'check_in_reminder' or 'observer_alert'
  timestamp: string;        // ISO timestamp
}
```

### 3. Enhanced Weekly Cleanup (`tokenCleanup.ts`)

**Three-Tier Cleanup Strategy:**
1. **Age-based**: Remove tokens older than 270 days
2. **Strike-based**: Remove tokens with 2+ accumulated strikes
3. **Validity-based**: Test with intelligent error categorization

**New Functions:**
- `shouldRemoveToken()` - Replaces aggressive dry-run testing
- Enhanced `cleanupUserTokens()` - Multi-tier cleanup logic

### 4. Daily Metrics Processing (`metricsProcessor.ts`)

**New Scheduled Function:** `processDailyTokenMetrics`
- Runs daily at 1 AM UTC
- Processes raw events into actionable insights
- Auto-cleanup of old data

**Data Retention Strategy:**
- Raw token events: 30 days (detailed debugging)
- Daily metrics: 90 days (trend analysis)

## New Firestore Collections

### `token_events` Collection
**Purpose**: Raw event data for detailed analysis
**Document Structure**:
```javascript
{
  userId: "user123",
  userName: "John Doe",
  token: "abc123...",
  eventType: "strike|error|removal",
  reason: "messaging/invalid-registration-token", 
  details: { strikeNumber: 2, totalStrikes: 2 },
  context: "check_in_reminder",
  timestamp: "2025-01-15T10:30:00.000Z"
}
```

### `daily_metrics` Collection
**Purpose**: Processed daily summaries
**Document ID Format**: `token_metrics_YYYY-MM-DD`
**Document Structure**:
```javascript
{
  date: "2025-01-15",
  timestamp: ServerTimestamp,
  tokenRemovals: {
    totalRemovals: 5,
    removalReasons: {
      strike_threshold: 3,
      age_limit: 1, 
      invalid_token: 1
    },
    affectedUsers: 3,
    userDetails: [
      {
        userId: "user123",
        userName: "John Doe",
        reason: "strike_threshold",
        context: "check_in_reminder"
      }
    ]
  },
  tokenErrors: {
    totalErrors: 15,
    totalStrikes: 8,
    errorTypes: {
      temporary_network: 10,
      invalid_token: 5
    },
    errorsByContext: {
      check_in_reminder: 12,
      observer_alert: 3
    }
  },
  userImpact: {
    usersWithTokenIssues: 5,
    userDetails: [
      {
        userId: "user123", 
        userName: "John Doe",
        userRole: "responder",
        totalStrikes: 2,
        tokensWithIssues: 1,
        totalTokens: 2
      }
    ]
  },
  systemSummary: {
    totalActiveUsers: 150,
    totalTokens: 300,
    healthyTokens: 285,
    tokensWithStrikes: 15,
    tokenHealthPercentage: "95.0"
  }
}
```

## Automatic Cloud Actions

### Real-time (During FCM Operations)
1. **Strike Application**: Definitive errors increment strike count
2. **Strike Reset**: Successful sends clear all strikes  
3. **Event Logging**: All errors and strikes logged to `token_events`
4. **Intelligent Removal**: Only after 3 definitive strikes

### Daily (1 AM UTC)
1. **Metrics Processing**: Raw events → daily summaries
2. **Event Cleanup**: Remove events older than 30 days
3. **Metrics Cleanup**: Remove daily summaries older than 90 days

### Weekly (Sunday 2 AM UTC)  
1. **Enhanced Token Cleanup**: Age + strikes + intelligent validation
2. **System Health Analysis**: Token age and strike distribution
3. **Batch Removal**: Problematic tokens with 2+ strikes

## Available Metrics & Insights

### User Impact Analysis
- **Users with chronic token issues**: High strike counts
- **User names**: Easy identification for support outreach
- **Role correlation**: Do responders vs observers have different patterns?
- **Timeline analysis**: When do users typically lose tokens?

### Error Pattern Analysis  
- **Temporary vs definitive errors**: Ratio indicates system health
- **Context analysis**: Do check-in reminders or observer alerts fail more?
- **Error code trends**: Which specific FCM errors are most common?
- **Geographic patterns**: (Future) Correlate with user locations

### System Health Monitoring
- **Token health percentage**: Overall system reliability
- **Removal rate trends**: Are token removals increasing?
- **Strike accumulation**: Early warning for problematic tokens
- **Age distribution**: How long do tokens typically last?

## Querying Strategies

### Real-time Investigation (token_events)
```javascript
// Users with recent strikes
db.collection('token_events')
  .where('eventType', '==', 'strike')
  .where('timestamp', '>=', last24Hours)
  .orderBy('timestamp', 'desc')

// Context-specific errors  
db.collection('token_events')
  .where('context', '==', 'check_in_reminder')
  .where('eventType', '==', 'error')
  .where('timestamp', '>=', lastWeek)
```

### Trend Analysis (daily_metrics)
```javascript
// Token health trends over time
db.collection('daily_metrics')
  .where('date', '>=', '2025-01-01')
  .orderBy('date', 'desc')
  .select('systemSummary.tokenHealthPercentage')

// Users frequently affected by removals
db.collection('daily_metrics')
  .where('date', '>=', lastMonth) 
  .select('tokenRemovals.userDetails')
```

### User-Specific Analysis
```javascript
// Specific user's token history
db.collection('token_events')
  .where('userId', '==', 'user123')
  .orderBy('timestamp', 'desc')

// Users needing support outreach
db.collection('daily_metrics')
  .where('date', '==', yesterday)
  .select('userImpact.userDetails')
  .where('userImpact.userDetails.totalStrikes', '>', 0)
```

## Implementation Benefits

### For Users
- **Resilient notifications**: Temporary connectivity doesn't break notifications
- **Better user experience**: Fewer "why aren't I getting notifications?" support tickets
- **Fair system**: Only actually invalid tokens get removed

### For Operations  
- **User identification**: Know exactly which users need help
- **Proactive support**: Reach out to users with chronic issues
- **System optimization**: Identify patterns for infrastructure improvements
- **Cost optimization**: Reduce unnecessary FCM token regeneration

### For Development
- **Debugging capability**: Detailed logs for troubleshooting
- **Performance monitoring**: Track system health over time  
- **Feature validation**: Measure impact of notification changes
- **User behavior insights**: Understanding connectivity patterns

## Python Integration Considerations

The Python admin tools should be enhanced to:

### Data Analysis Capabilities
- Query and visualize daily metrics trends
- Identify users needing support intervention
- Generate token health reports
- Export user impact summaries

### Administrative Actions
- Manually reset user strikes when appropriate
- Force token cleanup for specific users
- Generate user communication lists (users with chronic issues)
- Validate system health metrics

### Monitoring Alerts
- Alert when token health drops below threshold
- Notify when specific users accumulate strikes
- Report on unusual error pattern spikes
- Track cleanup effectiveness

## Future Enhancement Opportunities

### Advanced Analytics
- Correlation with user geography/device types
- Predictive modeling for token failure
- A/B testing notification delivery strategies
- User engagement correlation with token health

### Enhanced User Support
- Automated user notification about token issues
- Self-service token refresh capabilities  
- Proactive user guidance for connectivity issues
- Integration with customer support systems

### System Optimization
- Dynamic retry strategies based on error patterns
- Intelligent notification timing based on user connectivity
- Load balancing across FCM infrastructure
- Advanced caching strategies for offline users

This comprehensive enhancement transforms FCM token management from a "best guess" system to a data-driven, user-friendly, and operationally transparent infrastructure.