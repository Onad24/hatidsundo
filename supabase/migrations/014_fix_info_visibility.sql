-- Migration 014: Fix driver/client info visibility
-- Adds missing RLS policies so:
-- 1. Riders can read the basic profile (name, avatar) of clients on their active trip
-- 2. Clients can explicitly read the name/avatar of their assigned rider from the users table

-- -----------------------------------------------------------------------
-- RIDERS: allow reading client's user record for an active/accepted trip
-- -----------------------------------------------------------------------
DROP POLICY IF EXISTS "Riders can view client profile on active trip" ON users;
CREATE POLICY "Riders can view client profile on active trip"
    ON users FOR SELECT
    USING (
        -- Allow rider to read a user whose id == client_id of an active trip assigned to this rider
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.rider_id = auth.uid()
              AND trips.client_id = users.id
              AND trips.status IN ('accepted', 'driver_arriving', 'in_progress')
        )
    );

-- -----------------------------------------------------------------------
-- CLIENTS: make sure they can read their assigned rider's user row
-- (policy already exists in 007 but re-creating with DROP IF EXISTS for safety)
-- -----------------------------------------------------------------------
DROP POLICY IF EXISTS "Clients can view assigned rider profile" ON users;
CREATE POLICY "Clients can view assigned rider profile"
    ON users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.client_id = auth.uid()
              AND trips.rider_id = users.id
              AND trips.status IN ('accepted', 'driver_arriving', 'in_progress')
        )
    );
