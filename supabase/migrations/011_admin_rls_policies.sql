-- =============================================================================
-- Admin RLS Policies (idempotent — safe to re-run)
-- Uses a SECURITY DEFINER function to avoid infinite recursion on users table
-- =============================================================================

-- Helper function: checks if current user is admin
-- SECURITY DEFINER runs as the function owner, bypassing RLS on users table
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- USERS: Admins can view all user profiles
DROP POLICY IF EXISTS "Admins can view all users" ON users;
CREATE POLICY "Admins can view all users" ON users
    FOR SELECT USING (is_admin());

-- RIDER PROFILES: Admins can view and update all rider profiles (for approvals)
DROP POLICY IF EXISTS "Admins can view all rider profiles" ON rider_profiles;
CREATE POLICY "Admins can view all rider profiles" ON rider_profiles
    FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS "Admins can update rider profiles" ON rider_profiles;
CREATE POLICY "Admins can update rider profiles" ON rider_profiles
    FOR UPDATE USING (is_admin());

-- TRIPS: Admins can view all trips
DROP POLICY IF EXISTS "Admins can view all trips" ON trips;
CREATE POLICY "Admins can view all trips" ON trips
    FOR SELECT USING (is_admin());

-- MONTHLY FEES: Admins can view and update all fees (for settlements)
DROP POLICY IF EXISTS "Admins can view all monthly fees" ON monthly_fees;
CREATE POLICY "Admins can view all monthly fees" ON monthly_fees
    FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS "Admins can update monthly fees" ON monthly_fees;
CREATE POLICY "Admins can update monthly fees" ON monthly_fees
    FOR UPDATE USING (is_admin());

-- FEE EVENTS: Admins can view all fee events
DROP POLICY IF EXISTS "Admins can view all fee events" ON fee_events;
CREATE POLICY "Admins can view all fee events" ON fee_events
    FOR SELECT USING (is_admin());

-- MESSAGES: Admins can view all messages
DROP POLICY IF EXISTS "Admins can view all messages" ON messages;
CREATE POLICY "Admins can view all messages" ON messages
    FOR SELECT USING (is_admin());
