-- Migration: Allow riders to accept pending trips
-- Issue: Riders can't update pending trips because rider_id IS NULL
-- The existing policy "Users access their own trips" requires auth.uid() = rider_id,
-- but for pending trips, rider_id is NULL, so the update is blocked.

-- =============================================================================
-- STEP 1: Add policy for riders to accept pending trips
-- =============================================================================

-- Policy to allow approved riders to UPDATE pending trips (for accepting rides)
CREATE POLICY "Approved riders can accept pending trips" ON trips
    FOR UPDATE 
    USING (
        -- Trip must be pending and unassigned
        status = 'pending' 
        AND rider_id IS NULL
        -- User must be an approved rider
        AND EXISTS (
            SELECT 1 FROM rider_profiles 
            WHERE rider_profiles.user_id = auth.uid() 
            AND rider_profiles.status = 'approved'
        )
    )
    WITH CHECK (
        -- After update, the rider_id must be set to the current user
        rider_id = auth.uid()
    );

-- =============================================================================
-- STEP 2: Add policy for clients to view their assigned rider's info
-- =============================================================================

-- Policy to allow clients to view the user profile of riders assigned to their trips
CREATE POLICY "Clients can view assigned rider profile" ON users
    FOR SELECT
    USING (
        -- User is a rider assigned to one of the client's trips
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.client_id = auth.uid()
            AND trips.rider_id = users.id
            AND trips.status IN ('accepted', 'driver_arriving', 'in_progress')
        )
    );

