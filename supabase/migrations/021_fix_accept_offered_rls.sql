-- Migration: Update RLS policy to allow riders to accept 'offered' trips
-- The previous policy only allowed updating 'pending' trips with NULL rider_id.
-- Now trips go through 'offered' status (with rider_id already set by match_driver),
-- so the policy must allow updating 'offered' trips where rider_id = auth.uid().

-- Drop the old policy
DROP POLICY IF EXISTS "Approved riders can accept pending trips" ON trips;

-- Create updated policy that handles both pending (legacy) and offered (new flow) trips
CREATE POLICY "Approved riders can accept pending trips" ON trips
    FOR UPDATE 
    USING (
        (
            -- New flow: trip is offered to this specific driver
            status = 'offered' 
            AND rider_id = auth.uid()
            AND EXISTS (
                SELECT 1 FROM rider_profiles 
                WHERE rider_profiles.user_id = auth.uid() 
                AND rider_profiles.status = 'approved'
            )
        )
        OR
        (
            -- Legacy flow: pending trip with no driver assigned
            status = 'pending' 
            AND rider_id IS NULL
            AND EXISTS (
                SELECT 1 FROM rider_profiles 
                WHERE rider_profiles.user_id = auth.uid() 
                AND rider_profiles.status = 'approved'
            )
        )
    )
    WITH CHECK (
        rider_id = auth.uid()
    );

-- Also update the client view policy to include 'offered' status
DROP POLICY IF EXISTS "Clients can view assigned rider profile" ON users;
CREATE POLICY "Clients can view assigned rider profile" ON users
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.client_id = auth.uid()
            AND trips.rider_id = users.id
            AND trips.status IN ('offered', 'accepted', 'driver_arriving', 'in_progress')
        )
    );
