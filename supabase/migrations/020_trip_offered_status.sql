-- Migration: Add 'offered' status to trip_status enum and offered_at column
-- This supports the driver accept/decline flow where trips are first
-- "offered" to a driver before they accept.

-- Add the new enum value
ALTER TYPE trip_status ADD VALUE IF NOT EXISTS 'offered' BEFORE 'accepted';

-- Add offered_at timestamp column
ALTER TABLE trips ADD COLUMN IF NOT EXISTS offered_at TIMESTAMPTZ;
