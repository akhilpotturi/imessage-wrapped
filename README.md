# iMessage Wrapped for macOS

A local-first macOS app for exploring personal iMessage analytics. The app reads
the user's Messages database in read-only mode and keeps analytics on the Mac.

## Product direction

The first release focuses on metadata:

- Top direct conversations and group chats
- Sent, received, and total message counts
- Date-range filtering
- Per-conversation activity trends
- Contact name resolution that combines phone and email conversations belonging
  to the same contact

Message-content analysis and optional LLM integrations are intentionally a later
feature set with separate, explicit consent.

## Architecture

- **SwiftUI** provides the dashboard and conversation detail views.
- **MessageStore** owns read-only SQLite queries against
  `~/Library/Messages/chat.db`.
- **AppModel** coordinates permissions, date ranges, and loaded analytics.
- All aggregation runs locally. No backend is required for the core product.

The app sandbox is disabled because a sandboxed app cannot directly read the
Messages database. Distribution will therefore require Developer ID signing,
hardened runtime, and notarization rather than relying on a standard Mac App
Store sandbox.

## Development

Open `iMessageWrapped.xcodeproj` in Xcode and run the `iMessageWrapped` scheme.
Grant the built app Full Disk Access when prompted by the onboarding screen,
then relaunch it.
