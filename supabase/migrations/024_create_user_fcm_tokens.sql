-- Migration: Create the user_fcm_tokens table
-- This table stores Firebase Cloud Messaging device tokens so the server
-- can send push notifications to users (ride requests, trip updates, etc.)

CREATE TABLE IF NOT EXISTS user_fcm_tokens (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'android',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- Enable RLS
ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Users can manage their own tokens
CREATE POLICY "Users can insert their own FCM tokens" ON user_fcm_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own FCM tokens" ON user_fcm_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own FCM tokens" ON user_fcm_tokens
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own FCM tokens" ON user_fcm_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- Service role needs access for sending notifications from edge functions
-- (Edge functions use service role key which bypasses RLS, so no extra policy needed)

-- Auto-update timestamp
CREATE TRIGGER update_user_fcm_tokens_updated_at
    BEFORE UPDATE ON user_fcm_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Index for fast token lookup by user_id (used when sending notifications)
CREATE INDEX idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);
