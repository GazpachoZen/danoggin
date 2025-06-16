# Danoggin Release Notes

## [0.1.0 build 28] 2025-06-15
### Changes
- Made it much harder to do accidental double-submits
- Updated architecture for providing new questions after receipt of notification
- Improved logic on server for FCM token problems
- Changed the answer options from circles to rounded squares
- Added new puzzle packs (making change, colored colors)

## [0.1.0 build 28] 2025-05-29
### Changes
- The "about" page now generated locally
- Added this changelog to above
- Changes to how font sizes are calculated for check-in answers
- Added debug button to perform full app reset
### Internal
- Assorted code optimizations and better linting
- Complete refactor of cloud functionality

## [0.1.0] 2025-05-23
### Added
- Initial release of Danoggin cognitive check-in application
- Question-based check-ins with multiple-choice answers
- Responder (Main User) and Observer (Support Partner) roles
- Scheduled notifications to prompt check-ins
- Real-time monitoring of responder performance
- Question pack subscription system
- Invite code system for linking responders and observers
- Configurable active hours and check-in frequency
- Sound feedback for quiz responses
- FCM (Firebase Cloud Messaging) notification pipeline
- Inactivity monitoring and alerts for observers
- Cross-platform support (iOS and Android)
### Technical Features
- Firebase backend integration (Firestore, Auth, Storage, Messaging)
- Offline-capable question delivery
- Timezone-aware scheduling
- Comprehensive logging and debugging tools
- Local and cloud notification systems
### User Experience
- Intuitive role-based interfaces
- Easy relationship management between users
- Customizable notification preferences
- Built-in help and legal information
- Responsive design for various screen sizes
