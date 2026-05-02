-- Migration: Revert RLS policy to pending-only acceptance (remove offered flow)
-- The "offered" status is no longer used. Trips stay "pending" and are broadcast
-- to all nearby riders. First rider to accept wins (first-come-first-served).

-- Drop the old policy that handled both pending and offered
DROP POLICY IF EXISTS "Approved riders can accept pending trips" ON trips;

-- Simplified policy: only allow accepting pending trips with no rider assigned
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

-- Update client view policy to remove 'offered' from visible statuses
DROP POLICY IF EXISTS "Clients can view assigned rider profile" ON users;
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
