-- =============================================================================
-- Fare Settings Table (singleton — always id=1)
-- =============================================================================

CREATE TABLE fare_settings (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- enforce single row
    base_fare DECIMAL(10, 2) NOT NULL DEFAULT 25.0,
    per_km_rate DECIMAL(10, 2) NOT NULL DEFAULT 8.0,
    night_rate_multiplier DECIMAL(5, 2) NOT NULL DEFAULT 1.2,
    night_start_hour INT NOT NULL DEFAULT 21 CHECK (night_start_hour >= 0 AND night_start_hour <= 23),
    night_end_hour INT NOT NULL DEFAULT 5 CHECK (night_end_hour >= 0 AND night_end_hour <= 23),
    platform_fee_percent DECIMAL(5, 4) NOT NULL DEFAULT 0.10,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID REFERENCES users(id)
);

-- Insert default settings row
INSERT INTO fare_settings (id, base_fare, per_km_rate, night_rate_multiplier, night_start_hour, night_end_hour, platform_fee_percent)
VALUES (1, 25.0, 8.0, 1.2, 21, 5, 0.10);

-- Trigger to auto-update updated_at
CREATE TRIGGER update_fare_settings_updated_at
    BEFORE UPDATE ON fare_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE fare_settings ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read (needed for fare estimates on client side)
CREATE POLICY "Authenticated users can read fare settings"
    ON fare_settings FOR SELECT
    USING (auth.role() = 'authenticated');

-- Only admins can update
CREATE POLICY "Admins can update fare settings"
    ON fare_settings FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
        )
    );
