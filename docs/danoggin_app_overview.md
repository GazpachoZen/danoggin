# Danoggin App: Complete Overview and User Guide

## What is Danoggin?

Danoggin is a Flutter-based mobile application designed to provide **discrete safety monitoring** through regular cognitive check-ins. The app creates a safety net by connecting individuals who need monitoring (called "Responders" or "Main Users") with trusted people who can watch over them (called "Observers" or "Support Partners").

### Core Concept
The app works by sending periodic quiz questions to the main user. Their ability to correctly answer these questions serves as proof that they are alert, conscious, and functioning normally. If they miss questions or answer incorrectly, their support network is automatically notified.

### Primary Use Cases
- **Medical Monitoring:** Individuals with health conditions that could cause sudden incapacitation
- **Safety Monitoring:** People in potentially dangerous situations or environments
- **Wellness Checks:** General safety monitoring for vulnerable individuals
- **Remote Care:** Family members monitoring elderly relatives or those living alone
- **Professional Safety:** Workers in isolated or hazardous environments

---

## How Danoggin Works

### The Check-in System
1. **Scheduled Prompts:** The app sends notifications at regular intervals (default: every 5 minutes)
2. **Cognitive Questions:** Users answer simple questions from various question packs
3. **Response Window:** Users have a limited time to respond (default: 1 minute)
4. **Alert System:** Missed or incorrect responses trigger notifications to observers
5. **Automatic Rescheduling:** The system calculates the next check-in time based on user settings

### Question System
- **Multiple Choice Format:** Each question has one correct answer and three decoys
- **Question Packs:** Users can subscribe to different themed question sets
- **Progressive Difficulty:** Questions are designed to require active cognitive engagement
- **Retry Logic:** Users get a second chance if they answer incorrectly on the first attempt

### Active Hours
- **Customizable Schedule:** Users set their active monitoring hours (e.g., 8 AM to 8 PM)
- **Time Zone Aware:** System respects user's local time zone
- **Automatic Suspension:** No check-ins outside of active hours
- **Smart Rescheduling:** Next check-in automatically scheduled for the start of next active period

---

## User Roles and Experiences

## Responder (Main User) Experience

### Initial Setup
1. **Role Selection:** Choose "Main User" during onboarding
2. **Profile Creation:** Enter name and basic information
3. **Settings Configuration:**
   - Set active hours (when monitoring should occur)
   - Choose check-in frequency (1-360 minutes)
   - Set response timeout (0.5-15 minutes)
   - Enable/disable question feedback sounds
4. **Question Pack Selection:** Subscribe to desired question categories
5. **Invite Code Generation:** Receive a unique 6-character code for linking observers

### Daily Usage
1. **Background Operation:** App runs in background during active hours
2. **Check-in Notifications:** Receive periodic notifications to answer questions
3. **Question Answering:** Open app and select correct answer from multiple choices
4. **Immediate Feedback:** Get instant confirmation of correct/incorrect responses
5. **Retry Opportunities:** Second chance to answer if first attempt is wrong
6. **Automatic Progression:** System advances to next question after completion

### Key Features for Responders
- **Invite Code Sharing:** Share 6-character code with trusted observers
- **Observer Management:** View and remove people monitoring them
- **Settings Customization:** Adjust timing, difficulty, and notification preferences
- **Question Pack Management:** Subscribe/unsubscribe from different question categories
- **Real-time Feedback:** Audio and visual confirmation of responses
- **Emergency Override:** Manual refresh options in development mode

### Responder Settings Deep Dive
- **Active Hours:** Set specific times when check-ins should occur
- **Alert Frequency:** Configure interval between check-ins (5 minutes to 6 hours)
- **Response Timeout:** Set maximum time allowed to answer (30 seconds to 15 minutes)
- **Sound Preferences:** Enable/disable audio feedback for correct/incorrect answers
- **FCM Testing:** Built-in tools to verify notification delivery
- **Question Pack Subscriptions:** Choose from available question libraries

---

## Observer (Support Partner) Experience

### Initial Setup
1. **Role Selection:** Choose "Support Partner" during onboarding
2. **Profile Creation:** Enter name and contact information
3. **Responder Linking:** Enter invite codes from people they want to monitor
4. **Alert Preferences:** Configure inactivity threshold (6-72 hours, default 24)

### Monitoring Dashboard
1. **Responder Selection:** Choose which person to monitor (if monitoring multiple)
2. **Real-time Status:** View recent check-in history and results
3. **Alert Management:** Acknowledge issues when they arise
4. **Relationship Management:** Add or remove monitoring relationships

### Alert System
1. **Immediate Alerts:** Instant notifications for missed or incorrect check-ins
2. **Inactivity Alerts:** Notifications when responder hasn't been active for extended periods
3. **Context Information:** Alerts include responder name, time, and nature of issue
4. **Acknowledgment System:** Mark issues as acknowledged to stop repeat alerts

### Key Features for Observers
- **Multi-Responder Support:** Monitor multiple people simultaneously
- **Real-time Notifications:** Instant alerts for check-in issues
- **Historical Data:** View recent check-in patterns and trends
- **Flexible Alerting:** Configure inactivity thresholds
- **Relationship Management:** Easy linking/unlinking with responders
- **Badge Clearing:** Automatic notification cleanup when issues are acknowledged

### Observer Settings Deep Dive
- **Inactivity Threshold:** Set hours of inactivity before alert (6-72 hours)
- **Responder Management:** Add new people to monitor via invite codes
- **Notification Testing:** Verify alert delivery systems
- **FCM Integration:** Server-side notification system for reliable alerts

---

## Technical Architecture

### App Framework
- **Flutter:** Cross-platform mobile development
- **Firebase Backend:** Real-time database and cloud functions
- **Anonymous Authentication:** Secure but privacy-focused user management

### Notification System
- **Dual Approach:** Local notifications + Firebase Cloud Messaging (FCM)
- **Smart Delivery:** Context-aware notification selection (foreground vs background)
- **Platform Optimization:** iOS and Android specific optimizations
- **Reliability Measures:** Multiple notification strategies for guaranteed delivery

### Data Synchronization
- **Real-time Updates:** Instant synchronization between devices
- **Offline Capability:** Local storage with sync when connectivity returns
- **Cross-device Support:** Multiple devices per user supported
- **Backup and Recovery:** Cloud-based data persistence

---

## Key App Features

### Question Management
- **Dynamic Loading:** Questions loaded from cloud-based question packs
- **Randomization:** Questions presented in random order to prevent memorization
- **Pack Subscription:** Users can enable/disable different question categories
- **Content Updates:** Question packs can be updated remotely without app updates

### Relationship System
- **Invite-based Linking:** Secure connection system using unique codes
- **Bidirectional Management:** Both parties can manage the relationship
- **Multiple Connections:** Responders can have multiple observers, observers can monitor multiple responders
- **Privacy Controls:** Users control who can monitor them

### Notification Intelligence
- **Context Awareness:** Different notification strategies based on app state
- **Battery Optimization:** Efficient background processing
- **Do Not Disturb Respect:** Integration with system notification settings
- **Retry Logic:** Multiple attempts to ensure critical alerts are delivered

### Settings Synchronization
- **Cloud Backup:** Settings stored in Firebase for device transitions
- **Time Zone Handling:** Automatic detection and conversion for distributed teams
- **Preference Persistence:** All customizations maintained across app updates

---

## Safety and Privacy

### Privacy Protection
- **Anonymous IDs:** No personal information required beyond name
- **Local Processing:** Question answering happens on device
- **Minimal Data Collection:** Only essential monitoring data stored
- **User Control:** Complete control over who can monitor activities

### Security Measures
- **Secure Authentication:** Firebase-based authentication system
- **Encrypted Communication:** All data transmission encrypted
- **Access Controls:** Users only see their own data and authorized connections
- **Audit Trails:** Complete logging of all monitoring activities

### Emergency Considerations
- **Multiple Contact Points:** Support for multiple observers per responder
- **Escalation Paths:** Configurable alert thresholds for different urgency levels
- **Offline Tolerance:** System designed to handle temporary connectivity issues
- **Manual Overrides:** Emergency options for immediate assistance

---

## Development and Testing Features

### Debug Capabilities
- **Development Mode:** Special features for testing and debugging
- **Manual Triggers:** Force new questions for testing purposes
- **Notification Testing:** Built-in tools to verify delivery systems
- **Log Viewing:** Comprehensive logging for troubleshooting

### FCM Testing
- **Token Validation:** Verify Firebase Cloud Messaging setup
- **Delivery Confirmation:** Test notification delivery to specific devices
- **Pipeline Testing:** End-to-end notification system verification
- **Error Diagnosis:** Detailed error reporting for notification failures

---

## Use Case Scenarios

### Medical Monitoring
**Scenario:** Person with epilepsy needs monitoring during vulnerable periods
- **Setup:** Patient sets 10-minute check-ins during daytime hours
- **Monitoring:** Family member receives alerts for missed responses
- **Response:** Quick verification that person is conscious and responsive

### Remote Work Safety
**Scenario:** Field worker in isolated location needs safety monitoring
- **Setup:** Worker configures hourly check-ins during work shifts
- **Monitoring:** Supervisor receives alerts for missed check-ins
- **Response:** Immediate contact and potential emergency response if needed

### Elderly Care
**Scenario:** Adult child monitoring elderly parent living alone
- **Setup:** Parent sets gentle 2-hour intervals during waking hours
- **Monitoring:** Child receives notifications only when parent hasn't responded
- **Response:** Phone call or wellness visit triggered by missed check-ins

### Medication Management
**Scenario:** Person taking medication that affects cognitive function
- **Setup:** Regular check-ins timed around medication schedules
- **Monitoring:** Healthcare provider or family member alerted to issues
- **Response:** Assessment of medication effectiveness and safety

---

## Future Development Considerations

### Scalability Features
- **Question Pack Marketplace:** User-generated content and specialized packs
- **Integration APIs:** Connection with other health and safety systems
- **Advanced Analytics:** Pattern recognition for health trend monitoring
- **Professional Dashboard:** Enhanced features for healthcare providers

### Enhanced Monitoring
- **Biometric Integration:** Heart rate, movement, or other sensor data
- **Location Awareness:** GPS-based safety features
- **Voice Recognition:** Audio-based check-ins for accessibility
- **Adaptive Algorithms:** AI-powered adjustment of check-in frequency

---

## Summary

Danoggin represents a comprehensive approach to discrete safety monitoring that balances user autonomy with safety assurance. By using cognitive check-ins rather than passive monitoring, it respects user privacy while providing meaningful safety verification. The app's flexible configuration options, reliable notification system, and intuitive relationship management make it suitable for a wide range of monitoring scenarios, from medical supervision to workplace safety.

The technical architecture prioritizes reliability and user experience, with sophisticated notification systems, real-time data synchronization, and comprehensive error handling. Whether used for short-term safety monitoring or long-term care coordination, Danoggin provides a robust platform for connected safety monitoring.