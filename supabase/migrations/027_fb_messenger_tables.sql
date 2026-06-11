-- =============================================================================
-- Migration 027: Facebook Messenger Chatbot Support Tables
-- =============================================================================

-- Maps Facebook Page-Scoped IDs (PSIDs) to Supabase users.
-- A row is created the first time a user messages the bot.
-- user_id is NULL until the user completes a booking (auto-creates guest account).
CREATE TABLE IF NOT EXISTS fb_users (
  psid         TEXT PRIMARY KEY,
  user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  name         TEXT,
  first_name   TEXT,
  last_name    TEXT,
  avatar_url   TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fb_users_user_id ON fb_users(user_id);

-- Stores per-user conversational state for multi-step booking flows.
-- State machine values:
--   idle                 → no active flow
--   awaiting_pickup      → bot asked for pickup location
--   awaiting_destination → bot asked for destination
--   awaiting_vehicle     → bot asked for vehicle type
--   awaiting_confirm     → bot showed summary, waiting for confirm/cancel
--   handover             → thread passed to human agent
CREATE TABLE IF NOT EXISTS bot_sessions (
  psid        TEXT PRIMARY KEY REFERENCES fb_users(psid) ON DELETE CASCADE,
  state       TEXT NOT NULL DEFAULT 'idle',
  data        JSONB DEFAULT '{}',
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to keep updated_at fresh on fb_users
CREATE OR REPLACE FUNCTION update_fb_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_fb_users_updated_at ON fb_users;
CREATE TRIGGER trg_fb_users_updated_at
  BEFORE UPDATE ON fb_users
  FOR EACH ROW EXECUTE FUNCTION update_fb_users_updated_at();

-- Trigger to keep updated_at fresh on bot_sessions
CREATE OR REPLACE FUNCTION update_bot_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bot_sessions_updated_at ON bot_sessions;
CREATE TRIGGER trg_bot_sessions_updated_at
  BEFORE UPDATE ON bot_sessions
  FOR EACH ROW EXECUTE FUNCTION update_bot_sessions_updated_at();

-- RLS: only the service role (edge functions) may access these tables
ALTER TABLE fb_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_sessions ENABLE ROW LEVEL SECURITY;

-- Policies (drop first to be idempotent)
DROP POLICY IF EXISTS "Service role only" ON fb_users;
CREATE POLICY "Service role only" ON fb_users
  USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS "Service role only" ON bot_sessions;
CREATE POLICY "Service role only" ON bot_sessions
  USING (false) WITH CHECK (false);
