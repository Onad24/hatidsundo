-- Migration: Enable RLS and add policies
-- Run this to fix "violates row-level security policy" errors

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- POLICIES
-- =============================================================================

-- USERS: Users can view their own data, everyone can view basic driver info
CREATE POLICY "Users can view their own profile" ON users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON users
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Everyone can view driver names/avatars" ON users
    FOR SELECT USING (role = 'rider');

-- RIDER PROFILES: Publicly visible for approved riders
CREATE POLICY "Public view approved rider profiles" ON rider_profiles
    FOR SELECT USING (status = 'approved');

CREATE POLICY "Riders manage their own profile" ON rider_profiles
    FOR ALL USING (auth.uid() = user_id);

-- DRIVER LOCATIONS: Critical for "42501 Forbidden" error
CREATE POLICY "Drivers can update their own location" ON driver_locations
    FOR ALL USING (auth.uid() = driver_id);

CREATE POLICY "Authenticated users can view driver locations" ON driver_locations
    FOR SELECT TO authenticated USING (true);

-- TRIPS: Clients and Riders can view/update their own trips
CREATE POLICY "Users access their own trips" ON trips
    FOR ALL USING (auth.uid() = client_id OR auth.uid() = rider_id);

CREATE POLICY "Clients can create trips" ON trips
    FOR INSERT WITH CHECK (auth.uid() = client_id);

-- MESSAGES: Participants can access messages
CREATE POLICY "Participants access messages" ON messages
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM trips 
            WHERE trips.id = messages.trip_id 
            AND (trips.client_id = auth.uid() OR trips.rider_id = auth.uid())
        )
    );

-- NOTIFICATIONS: Users access their own notifications
CREATE POLICY "Users access own notifications" ON notifications
    FOR ALL USING (auth.uid() = user_id);

-- MONTHLY FEES: Riders view, Admins manage (Admins bypass RLS if using service role, but good to have)
CREATE POLICY "Riders view own fees" ON monthly_fees
    FOR SELECT USING (auth.uid() = rider_id);

-- FEE EVENTS: Riders view own events
CREATE POLICY "Riders view own events" ON fee_events
    FOR SELECT USING (auth.uid() = rider_id);
