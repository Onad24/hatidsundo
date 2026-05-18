# Hatid Sundo - Ride Hailing Application

A full-featured ride-hailing application built with Flutter and Supabase,
featuring client, rider (driver), and admin interfaces.

## Features

### Client App

- 🚗 Request rides with pickup/destination selection
- 📍 Real-time driver tracking on map
- 💬 In-trip chat with driver
- 📜 Trip history and receipts
- 🔔 Push notifications for trip updates

### Rider (Driver) App

- 🏠 Online/offline toggle with availability status
- 📱 Driver registration with document upload
- 🗺️ Turn-by-turn navigation
- 💰 Earnings dashboard
- 📊 Fee dashboard with outstanding dues
- ⚠️ Account lockout for unpaid fees

### Admin Web Dashboard

- 👥 Rider approval management
- 🗺️ Live map of all drivers
- 📈 Trip monitoring and statistics
- 💬 Message supervision
- 💵 Fee management and settlements
- 📊 CSV export capabilities

## Technology Stack

- **Frontend**: Flutter (Mobile + Web)
- **State Management**: Riverpod
- **Backend**: Supabase (PostgreSQL + PostGIS, Auth, Realtime, Edge Functions,
  Storage)
- **Maps**: MapLibre + OpenStreetMap tiles
- **Routing**: OSRM API
- **Push Notifications**: Firebase Cloud Messaging (FCM)

## Project Structure

```
lib/
├── main.dart                    # Main entry point
├── config/
│   └── env.dart                 # Environment configuration
├── core/
│   ├── constants.dart           # App constants
│   ├── router.dart              # GoRouter configuration
│   └── theme.dart               # App theme
├── models/                      # Data models
├── services/                    # Backend services
├── state/                       # Riverpod providers
├── widgets/                     # Shared widgets
├── client_app/                  # Client passenger screens
├── rider_app/                   # Driver screens
└── admin_web/                   # Admin dashboard screens

supabase/
├── migrations/                  # SQL schema and RLS policies
└── functions/                   # Edge Functions
```

## Getting Started

### Prerequisites

- Flutter SDK 3.19+
- Dart SDK 3.3+
- Supabase CLI
- Node.js 18+ (for Supabase Edge Functions)

### Environment Setup

Use `--dart-define` flags:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=OSRM_BASE_URL=https://router.project-osrm.org \
  --dart-define=GOOGLE_CLIENT_ID=your-client-id \
  --dart-define=APP_FLAVOR=client
```

### Supabase Setup

1. Create a new Supabase project
2. Run migrations:
   ```bash
   supabase db push
   ```
3. Deploy Edge Functions:
   ```bash
   supabase functions deploy match_driver
   supabase functions deploy complete_trip
   supabase functions deploy settle_fees
   ```
4. Enable PostGIS extension in your database

### Running the App

**Client App:**

```bash
flutter run --dart-define=APP_FLAVOR=client
```

**Rider App:**

```bash
flutter run --dart-define=APP_FLAVOR=rider
```

**Admin Web:**

```bash
flutter run -d chrome --dart-define=APP_FLAVOR=admin
```

## Fee System

The platform uses a 10% fee model:

- Fees are calculated on trip completion
- Monthly fees accrue in `monthly_fees` table
- Outstanding dues block drivers from going online
- Admin can settle fees via dashboard or Edge Function
- Monthly fee rollover runs automatically

## License

This project is proprietary software. All rights reserved.
# hatidsundo
# hatidsundo
# hatidsundo
# hatidsundo
# hatidsundo
