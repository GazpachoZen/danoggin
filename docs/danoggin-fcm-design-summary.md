# Danoggin FCM Implementation Design Summary

## Background and Current Status

The Danoggin app is a cognitive check-in application with two main user roles:
- **Responders**: Users who answer periodic quiz questions
- **Observers**: Users who monitor responders' performance on check-ins

The notification system has been refactored from a monolithic implementation to a modular architecture with:
- Clear separation between interfaces, implementation, and platform-specific code
- A central manager (`NotificationManager`) as a facade for all notification functionality
- Specialized components with single responsibilities

## Problem Statement

Despite the refactoring, iOS background notifications remain unreliable using local notifications, due to iOS restrictions on generating local notifications when apps are in the background. This limitation impacts core functionality for:
- Observers who need alerts about missed/incorrect check-ins
- Responders who need timely prompts to complete check-ins

## Proposed Solution: Firebase Cloud Messaging (FCM)

Implementation of Firebase Cloud Messaging, which uses Apple's Push Notification service (APNs) for iOS, will provide reliable background notifications because:
- Push notifications originate from a trusted server, not the app itself
- They can wake up an app even when it's completely inactive
- They work consistently across both Android and iOS

## Notification Requirements

1. **Responder Check-in Reminders**:
   - Scheduled based on configured intervals and active hours
   - Must respect time zones and user preferences

2. **Observer Alerts for Missed/Incorrect Check-ins**:
   - Notify all linked observers when a responder misses or incorrectly answers a check-in
   - Ensure timely delivery even when observer apps are in the background

3. **Testing Functionality**:
   - Maintain test buttons in the UI for development and debugging
   - Support testing of both local and FCM notifications

4. **Future: Observer-Initiated Check-ins**:
   - Allow observers to trigger immediate check-in requests for responders
   - Support for this future feature is a consideration in the current design

## Scalability Design: Time Bucket Approach

To support thousands of responders with unique schedules efficiently:

1. **Group users into time buckets** (e.g., 5 or 15-minute intervals)
2. **Run a single Cloud Function** for each bucket window
3. **Query and notify** all users whose next check-in falls within that window

### Database Structure for Scalability

```
users/
  {userId}/
    role: "responder"
    activeHoursStart: "08:00"
    activeHoursEnd: "20:00"
    timeZone: "America/New_York"
    checkInInterval: 120 // minutes
    nextCheckInTime: Timestamp // UTC
    // Other user fields

scheduleBuckets/
  {bucketTime}/
    userIds: [array of userIds due in this bucket]
```

### Schedule Adjustment Support

For responders to adjust their schedules:

1. **Update user document** with new preferences
2. **Recalculate nextCheckInTime** based on new settings
3. **Update bucket assignments** via Cloud Function trigger
4. **Provide immediate reset option** for changes to take effect quickly

## Implementation Plan

### 1. Server-Side Components

- **Cloud Functions for notification triggers**:
  - Time-based functions for scheduled check-ins
  - Firestore triggers for missed/incorrect check-in alerts
  - HTTP triggers for test notifications and observer-initiated checks

- **Scheduling Logic**:
  - Time bucket calculation and management
  - User timezone and active hours handling
  - Next check-in time calculation

### 2. Client-Side Integration

- **FCM Service Implementation**:
  - Token generation and storage
  - Notification handling for all app states
  - Integration with existing NotificationManager

- **User Interface Updates**:
  - Schedule visibility for responders
  - Immediate reset option for schedule changes
  - Test functionality preservation

### 3. Migration Strategy

- **Phased Approach**:
  - Implement FCM alongside existing local notifications
  - Gradually shift to FCM for critical notifications
  - Maintain backward compatibility during transition

## Advantages of This Approach

1. **Reliability**: Notifications delivered even when the app is terminated
2. **Scalability**: Efficiently handles thousands of users with unique schedules
3. **Flexibility**: Supports schedule adjustments and future features
4. **Consistency**: Similar experience across iOS and Android

## Technical Constraints and Considerations

1. **iOS Certification Requirements**:
   - APNs authentication key
   - Proper app capabilities in provisioning profile

2. **Batch Processing Efficiency**:
   - Optimized queries for bucket processing
   - Rate limiting considerations for FCM

3. **Edge Cases**:
   - Timezone changes
   - Temporary schedule pausing
   - Device token refreshing
