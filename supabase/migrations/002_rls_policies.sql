-- =============================================================================
-- Row Level Security (RLS) Policies
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_batches ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- HELPER FUNCTIONS FOR RLS
-- =============================================================================

-- Check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users 
        WHERE id = auth.uid() 
        AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if current user is rider
CREATE OR REPLACE FUNCTION is_rider()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users 
        WHERE id = auth.uid() 
        AND role = 'rider'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if rider is approved
CREATE OR REPLACE FUNCTION is_approved_rider()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM rider_profiles 
        WHERE user_id = auth.uid() 
        AND status = 'approved'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- USERS POLICIES
-- =============================================================================

-- Users can read their own profile
CREATE POLICY "Users can view own profile"
    ON users FOR SELECT
    USING (id = auth.uid());

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Admins can view all users
CREATE POLICY "Admins can view all users"
    ON users FOR SELECT
    USING (is_admin());

-- Admins can update all users
CREATE POLICY "Admins can update all users"
    ON users FOR UPDATE
    USING (is_admin());

-- Service role can insert users (via auth trigger)
CREATE POLICY "Service can insert users"
    ON users FOR INSERT
    WITH CHECK (true);

-- =============================================================================
-- RIDER PROFILES POLICIES
-- =============================================================================

-- Riders can view their own profile
CREATE POLICY "Riders can view own profile"
    ON rider_profiles FOR SELECT
    USING (user_id = auth.uid());

-- Riders can insert their own profile
CREATE POLICY "Riders can create own profile"
    ON rider_profiles FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Riders can update their own profile (limited fields)
CREATE POLICY "Riders can update own profile"
    ON rider_profiles FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Admins can view all profiles
CREATE POLICY "Admins can view all rider profiles"
    ON rider_profiles FOR SELECT
    USING (is_admin());

-- Admins can update all profiles (for approval)
CREATE POLICY "Admins can update rider profiles"
    ON rider_profiles FOR UPDATE
    USING (is_admin());

-- Clients can view approved riders (for trip info)
CREATE POLICY "Clients can view approved riders"
    ON rider_profiles FOR SELECT
    USING (status = 'approved');

-- =============================================================================
-- DRIVER LOCATIONS POLICIES
-- =============================================================================

-- Drivers can insert/update their own location
CREATE POLICY "Drivers can upsert own location"
    ON driver_locations FOR INSERT
    WITH CHECK (driver_id = auth.uid() AND is_approved_rider());

CREATE POLICY "Drivers can update own location"
    ON driver_locations FOR UPDATE
    USING (driver_id = auth.uid())
    WITH CHECK (driver_id = auth.uid());

-- Drivers can read their own location
CREATE POLICY "Drivers can view own location"
    ON driver_locations FOR SELECT
    USING (driver_id = auth.uid());

-- Clients can view online drivers (for nearby drivers)
CREATE POLICY "Clients can view online drivers"
    ON driver_locations FOR SELECT
    USING (is_online = true AND is_available = true);

-- Admins can view all driver locations
CREATE POLICY "Admins can view all driver locations"
    ON driver_locations FOR SELECT
    USING (is_admin());

-- =============================================================================
-- TRIPS POLICIES
-- =============================================================================

-- Clients can create trips
CREATE POLICY "Clients can create trips"
    ON trips FOR INSERT
    WITH CHECK (client_id = auth.uid());

-- Clients can view their own trips
CREATE POLICY "Clients can view own trips"
    ON trips FOR SELECT
    USING (client_id = auth.uid());

-- Riders can view trips assigned to them
CREATE POLICY "Riders can view assigned trips"
    ON trips FOR SELECT
    USING (rider_id = auth.uid());

-- Riders can view pending trips (for accepting)
CREATE POLICY "Riders can view pending trips"
    ON trips FOR SELECT
    USING (status = 'pending' AND is_approved_rider());

-- Riders can update trips assigned to them
CREATE POLICY "Riders can update assigned trips"
    ON trips FOR UPDATE
    USING (rider_id = auth.uid() OR (status = 'pending' AND rider_id IS NULL))
    WITH CHECK (rider_id = auth.uid() OR rider_id IS NULL);

-- Clients can update their own trips (cancel, rate)
CREATE POLICY "Clients can update own trips"
    ON trips FOR UPDATE
    USING (client_id = auth.uid())
    WITH CHECK (client_id = auth.uid());

-- Admins can view and update all trips
CREATE POLICY "Admins can view all trips"
    ON trips FOR SELECT
    USING (is_admin());

CREATE POLICY "Admins can update all trips"
    ON trips FOR UPDATE
    USING (is_admin());

-- =============================================================================
-- MESSAGES POLICIES
-- =============================================================================

-- Trip participants can view messages
CREATE POLICY "Trip participants can view messages"
    ON messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM trips t 
            WHERE t.id = trip_id 
            AND (t.client_id = auth.uid() OR t.rider_id = auth.uid())
        )
    );

-- Trip participants can send messages
CREATE POLICY "Trip participants can send messages"
    ON messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM trips t 
            WHERE t.id = trip_id 
            AND (t.client_id = auth.uid() OR t.rider_id = auth.uid())
        )
    );

-- Users can update their own messages (mark as read)
CREATE POLICY "Users can update read status"
    ON messages FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM trips t 
            WHERE t.id = trip_id 
            AND (t.client_id = auth.uid() OR t.rider_id = auth.uid())
        )
    );

-- Admins can view all messages
CREATE POLICY "Admins can view all messages"
    ON messages FOR SELECT
    USING (is_admin());

-- Admins can send messages (supervision)
CREATE POLICY "Admins can send messages"
    ON messages FOR INSERT
    WITH CHECK (is_admin());

-- =============================================================================
-- MONTHLY FEES POLICIES
-- =============================================================================

-- Riders can view their own fees
CREATE POLICY "Riders can view own fees"
    ON monthly_fees FOR SELECT
    USING (rider_id = auth.uid());

-- Admins can view all fees
CREATE POLICY "Admins can view all fees"
    ON monthly_fees FOR SELECT
    USING (is_admin());

-- Admins can update fees (settlements)
CREATE POLICY "Admins can update fees"
    ON monthly_fees FOR UPDATE
    USING (is_admin());

-- System can insert fees (via triggers)
CREATE POLICY "System can insert fees"
    ON monthly_fees FOR INSERT
    WITH CHECK (true);

-- =============================================================================
-- FEE EVENTS POLICIES
-- =============================================================================

-- Riders can view their own fee events
CREATE POLICY "Riders can view own fee events"
    ON fee_events FOR SELECT
    USING (rider_id = auth.uid());

-- Admins can view all fee events
CREATE POLICY "Admins can view all fee events"
    ON fee_events FOR SELECT
    USING (is_admin());

-- Admins can create fee events (adjustments)
CREATE POLICY "Admins can create fee events"
    ON fee_events FOR INSERT
    WITH CHECK (is_admin());

-- =============================================================================
-- NOTIFICATIONS POLICIES
-- =============================================================================

-- Users can view their own notifications
CREATE POLICY "Users can view own notifications"
    ON notifications FOR SELECT
    USING (user_id = auth.uid());

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update own notifications"
    ON notifications FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- System/admins can create notifications
CREATE POLICY "System can create notifications"
    ON notifications FOR INSERT
    WITH CHECK (true);

-- =============================================================================
-- LOCATION BATCHES POLICIES
-- =============================================================================

-- Drivers can insert their own location batches
CREATE POLICY "Drivers can insert location batches"
    ON location_batches FOR INSERT
    WITH CHECK (driver_id = auth.uid());

-- Drivers can view their own location batches
CREATE POLICY "Drivers can view own location batches"
    ON location_batches FOR SELECT
    USING (driver_id = auth.uid());

-- Admins can view all location batches
CREATE POLICY "Admins can view all location batches"
    ON location_batches FOR SELECT
    USING (is_admin());
