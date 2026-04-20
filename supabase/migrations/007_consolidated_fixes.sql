-- Consolidated migration to fix Accept Ride and Driver Info Visibility
-- Combines previous fixes and ensures clean state

-- 1. DROP existing policies to avoid conflicts (in case they were partially run)
DROP POLICY IF EXISTS "Approved riders can accept pending trips" ON trips;
DROP POLICY IF EXISTS "Clients can view assigned rider profile" ON users;

-- 2. Allow approved riders to accept pending trips
CREATE POLICY "Approved riders can accept pending trips" ON trips
    FOR UPDATE 
    USING (
        status = 'pending' 
        AND rider_id IS NULL
        AND EXISTS (
            SELECT 1 FROM rider_profiles 
            WHERE rider_profiles.user_id = auth.uid() 
            AND rider_profiles.status = 'approved'
        )
    )
    WITH CHECK (
        rider_id = auth.uid()
    );

-- 3. Allow clients to view their assigned rider's profile
CREATE POLICY "Clients can view assigned rider profile" ON users
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.client_id = auth.uid()
            AND trips.rider_id = users.id
            AND trips.status IN ('accepted', 'driver_arriving', 'in_progress')
        )
    );

-- 4. Ensure the specific test rider is approved (Replace ID if different, but using the one from logs)
UPDATE rider_profiles
SET status = 'approved',
    updated_at = NOW()
WHERE user_id = '2438cc01-d4d4-4dbf-a302-7cc973ed0a7f';

-- 5. OPTIONAL: Reset any "stuck" pending trips that might have bad data
-- (e.g. pending but have a rider_id assigned)
UPDATE trips
SET rider_id = NULL
WHERE status = 'pending' AND rider_id IS NOT NULL;
