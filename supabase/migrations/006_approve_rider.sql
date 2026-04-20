-- Migration: Manually approve rider to unblock testing
-- Issue: Rider cannot accept trips or show profile because status != 'approved'

-- Update the specific rider to 'approved'
UPDATE rider_profiles
SET status = 'approved',
    updated_at = NOW()
WHERE user_id = '2438cc01-d4d4-4dbf-a302-7cc973ed0a7f';

-- Verify the update
SELECT * FROM rider_profiles WHERE user_id = '2438cc01-d4d4-4dbf-a302-7cc973ed0a7f';
