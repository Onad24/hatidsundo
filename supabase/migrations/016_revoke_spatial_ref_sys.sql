-- Migration 016: Revoke API access to spatial_ref_sys
-- This prevents the public/API from querying the PostGIS system table
-- and resolves the security exposure that Supabase is warning about.

REVOKE ALL ON TABLE public.spatial_ref_sys FROM anon, authenticated, public;
