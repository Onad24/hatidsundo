-- Migration: Ensure Realtime delivers complete row data for trips
-- Without REPLICA IDENTITY FULL, UPDATE events via Supabase Realtime
-- may not include all columns in the newRecord payload, causing
-- TripModel.fromJson to fail or produce incomplete objects.

ALTER TABLE trips REPLICA IDENTITY FULL;
ALTER TABLE driver_locations REPLICA IDENTITY FULL;
ALTER TABLE messages REPLICA IDENTITY FULL;
