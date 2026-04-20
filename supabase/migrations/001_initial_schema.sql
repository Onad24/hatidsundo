-- =============================================================================
-- Hatid Sundo - Ride Hailing Application Database Schema
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- =============================================================================
-- ENUMS
-- =============================================================================

CREATE TYPE user_role AS ENUM ('client', 'rider', 'admin');
CREATE TYPE rider_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
CREATE TYPE trip_status AS ENUM ('pending', 'accepted', 'driver_arriving', 'in_progress', 'completed', 'cancelled');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'refunded');
CREATE TYPE sender_role AS ENUM ('client', 'rider', 'admin', 'system');
CREATE TYPE notification_type AS ENUM ('ride_request', 'driver_assigned', 'driver_arriving', 'trip_started', 'trip_completed', 'payment', 'fee_reminder', 'account_lockout', 'message', 'admin_alert');

-- =============================================================================
-- USERS TABLE
-- =============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    phone TEXT,
    avatar_url TEXT,
    role user_role NOT NULL DEFAULT 'client',
    fcm_token TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for role-based queries
CREATE INDEX idx_users_role ON users(role);

-- =============================================================================
-- RIDER PROFILES TABLE
-- =============================================================================

CREATE TABLE rider_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    
    -- Vehicle information
    vehicle_type TEXT NOT NULL, -- motorcycle, sedan, suv
    vehicle_make TEXT NOT NULL,
    vehicle_model TEXT NOT NULL,
    vehicle_year INTEGER,
    vehicle_color TEXT,
    plate_number TEXT NOT NULL,
    
    -- License information
    license_number TEXT NOT NULL,
    license_expiry DATE,
    
    -- Documents (stored in Supabase Storage)
    license_photo_url TEXT,
    vehicle_photo_url TEXT,
    or_cr_photo_url TEXT,
    selfie_url TEXT,
    
    -- Status
    status rider_status DEFAULT 'pending',
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES users(id),
    rejection_reason TEXT,
    
    -- Rating
    rating DECIMAL(3, 2) DEFAULT 5.0,
    total_trips INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for status queries
CREATE INDEX idx_rider_profiles_status ON rider_profiles(status);
CREATE INDEX idx_rider_profiles_user_id ON rider_profiles(user_id);

-- =============================================================================
-- DRIVER LOCATIONS TABLE (Real-time tracking)
-- =============================================================================

CREATE TABLE driver_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Location using PostGIS
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION DEFAULT 0,
    speed DOUBLE PRECISION DEFAULT 0,
    accuracy DOUBLE PRECISION,
    
    -- Status
    is_online BOOLEAN DEFAULT false,
    is_available BOOLEAN DEFAULT false,
    current_trip_id UUID,
    
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Spatial index for nearby driver queries
CREATE INDEX idx_driver_locations_location ON driver_locations USING GIST(location);
CREATE INDEX idx_driver_locations_driver_id ON driver_locations(driver_id);
CREATE INDEX idx_driver_locations_online ON driver_locations(is_online, is_available);

-- =============================================================================
-- TRIPS TABLE
-- =============================================================================

CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Participants
    client_id UUID NOT NULL REFERENCES users(id),
    rider_id UUID REFERENCES users(id),
    
    -- Pickup location
    pickup_lat DOUBLE PRECISION NOT NULL,
    pickup_lng DOUBLE PRECISION NOT NULL,
    pickup_address TEXT,
    pickup_location GEOGRAPHY(POINT, 4326),
    
    -- Destination
    dest_lat DOUBLE PRECISION NOT NULL,
    dest_lng DOUBLE PRECISION NOT NULL,
    dest_address TEXT,
    dest_location GEOGRAPHY(POINT, 4326),
    
    -- Route information
    distance_km DOUBLE PRECISION,
    duration_min INTEGER,
    route_polyline TEXT,
    
    -- Fare
    fare_estimated DECIMAL(10, 2) NOT NULL,
    fare_final DECIMAL(10, 2),
    platform_fee DECIMAL(10, 2),
    
    -- Status
    status trip_status DEFAULT 'pending',
    payment_status payment_status DEFAULT 'pending',
    
    -- Timestamps
    accepted_at TIMESTAMPTZ,
    pickup_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID REFERENCES users(id),
    cancellation_reason TEXT,
    
    -- Rating
    client_rating INTEGER CHECK (client_rating >= 1 AND client_rating <= 5),
    rider_rating INTEGER CHECK (rider_rating >= 1 AND rider_rating <= 5),
    client_comment TEXT,
    rider_comment TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_trips_client_id ON trips(client_id);
CREATE INDEX idx_trips_rider_id ON trips(rider_id);
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_created_at ON trips(created_at DESC);
CREATE INDEX idx_trips_pickup_location ON trips USING GIST(pickup_location);

-- =============================================================================
-- MESSAGES TABLE (Trip-scoped chat)
-- =============================================================================

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    sender_role sender_role NOT NULL,
    
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text', -- text, location, image
    metadata JSONB,
    
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_messages_trip_id ON messages(trip_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);

-- =============================================================================
-- MONTHLY FEES TABLE
-- =============================================================================

CREATE TABLE monthly_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES users(id),
    
    -- Period
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
    
    -- Amounts
    accrued_fee DECIMAL(10, 2) DEFAULT 0,
    due_amount DECIMAL(10, 2) DEFAULT 0,
    paid_amount DECIMAL(10, 2) DEFAULT 0,
    
    -- Status
    is_settled BOOLEAN DEFAULT false,
    settled_at TIMESTAMPTZ,
    settled_by UUID REFERENCES users(id),
    
    -- Rollover
    rolled_over_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(rider_id, year, month)
);

-- Indexes
CREATE INDEX idx_monthly_fees_rider_id ON monthly_fees(rider_id);
CREATE INDEX idx_monthly_fees_period ON monthly_fees(year, month);
CREATE INDEX idx_monthly_fees_unsettled ON monthly_fees(is_settled) WHERE NOT is_settled;

-- =============================================================================
-- FEE EVENTS TABLE
-- =============================================================================

CREATE TABLE fee_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES users(id),
    monthly_fee_id UUID REFERENCES monthly_fees(id),
    trip_id UUID REFERENCES trips(id),
    
    amount DECIMAL(10, 2) NOT NULL,
    event_type TEXT NOT NULL, -- trip_fee, adjustment, credit, settlement
    description TEXT,
    
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_fee_events_rider_id ON fee_events(rider_id);
CREATE INDEX idx_fee_events_monthly_fee_id ON fee_events(monthly_fee_id);

-- =============================================================================
-- NOTIFICATIONS TABLE
-- =============================================================================

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    payload JSONB,
    
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE NOT is_read;

-- =============================================================================
-- LOCATION BATCHES TABLE (GPS batch uploads)
-- =============================================================================

CREATE TABLE location_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES users(id),
    trip_id UUID REFERENCES trips(id),
    
    updates JSONB NOT NULL, -- Array of location updates
    batch_size INTEGER NOT NULL,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index
CREATE INDEX idx_location_batches_driver_id ON location_batches(driver_id);
CREATE INDEX idx_location_batches_trip_id ON location_batches(trip_id);

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function to get nearby available drivers
CREATE OR REPLACE FUNCTION get_nearby_drivers(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 5
)
RETURNS TABLE (
    driver_id UUID,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    distance_km DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dl.driver_id,
        dl.lat,
        dl.lng,
        dl.heading,
        ST_Distance(
            dl.location::geography,
            ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
        ) / 1000 AS distance_km
    FROM driver_locations dl
    JOIN rider_profiles rp ON dl.driver_id = rp.user_id
    WHERE dl.is_online = true
      AND dl.is_available = true
      AND dl.current_trip_id IS NULL
      AND rp.status = 'approved'
      AND ST_DWithin(
          dl.location::geography,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          p_radius_km * 1000
      )
    ORDER BY distance_km ASC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate outstanding fees for a rider
CREATE OR REPLACE FUNCTION get_outstanding_fees(p_rider_id UUID)
RETURNS DECIMAL(10, 2) AS $$
DECLARE
    total DECIMAL(10, 2);
BEGIN
    SELECT COALESCE(SUM(due_amount - paid_amount), 0)
    INTO total
    FROM monthly_fees
    WHERE rider_id = p_rider_id
      AND is_settled = false;
    
    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- Function to check if rider has outstanding dues
CREATE OR REPLACE FUNCTION has_outstanding_dues(p_rider_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_outstanding_fees(p_rider_id) > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to rollover monthly fees
CREATE OR REPLACE FUNCTION rollover_monthly_fees()
RETURNS void AS $$
DECLARE
    current_year INTEGER;
    current_month INTEGER;
    prev_year INTEGER;
    prev_month INTEGER;
BEGIN
    current_year := EXTRACT(YEAR FROM NOW());
    current_month := EXTRACT(MONTH FROM NOW());
    
    -- Calculate previous month
    IF current_month = 1 THEN
        prev_year := current_year - 1;
        prev_month := 12;
    ELSE
        prev_year := current_year;
        prev_month := current_month - 1;
    END IF;
    
    -- Rollover unsettled fees from previous month
    UPDATE monthly_fees
    SET 
        rolled_over_at = NOW(),
        updated_at = NOW()
    WHERE year = prev_year
      AND month = prev_month
      AND is_settled = false
      AND rolled_over_at IS NULL;
    
    -- Add due amount to new month records
    INSERT INTO monthly_fees (rider_id, year, month, due_amount)
    SELECT 
        rider_id,
        current_year,
        current_month,
        (accrued_fee + due_amount - paid_amount)
    FROM monthly_fees
    WHERE year = prev_year
      AND month = prev_month
      AND is_settled = false
      AND (accrued_fee + due_amount - paid_amount) > 0
    ON CONFLICT (rider_id, year, month)
    DO UPDATE SET
        due_amount = monthly_fees.due_amount + EXCLUDED.due_amount,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update timestamp triggers
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_rider_profiles_updated_at
    BEFORE UPDATE ON rider_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_trips_updated_at
    BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_monthly_fees_updated_at
    BEFORE UPDATE ON monthly_fees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Trigger to update driver_locations geography from lat/lng
CREATE OR REPLACE FUNCTION update_driver_location_geography()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_driver_location_geography
    BEFORE INSERT OR UPDATE OF lat, lng ON driver_locations
    FOR EACH ROW EXECUTE FUNCTION update_driver_location_geography();

-- Trigger to update trip geography from lat/lng
CREATE OR REPLACE FUNCTION update_trip_geography()
RETURNS TRIGGER AS $$
BEGIN
    NEW.pickup_location = ST_SetSRID(ST_MakePoint(NEW.pickup_lng, NEW.pickup_lat), 4326)::geography;
    NEW.dest_location = ST_SetSRID(ST_MakePoint(NEW.dest_lng, NEW.dest_lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_trip_geography
    BEFORE INSERT OR UPDATE OF pickup_lat, pickup_lng, dest_lat, dest_lng ON trips
    FOR EACH ROW EXECUTE FUNCTION update_trip_geography();

-- Trigger to add trip fee to monthly fees
CREATE OR REPLACE FUNCTION add_trip_fee()
RETURNS TRIGGER AS $$
DECLARE
    platform_fee_amount DECIMAL(10, 2);
    current_year INTEGER;
    current_month INTEGER;
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Calculate platform fee (10%)
        platform_fee_amount := COALESCE(NEW.fare_final, NEW.fare_estimated) * 0.10;
        NEW.platform_fee := platform_fee_amount;
        
        current_year := EXTRACT(YEAR FROM NOW());
        current_month := EXTRACT(MONTH FROM NOW());
        
        -- Upsert monthly fee record
        INSERT INTO monthly_fees (rider_id, year, month, accrued_fee)
        VALUES (NEW.rider_id, current_year, current_month, platform_fee_amount)
        ON CONFLICT (rider_id, year, month)
        DO UPDATE SET
            accrued_fee = monthly_fees.accrued_fee + platform_fee_amount,
            updated_at = NOW();
        
        -- Create fee event
        INSERT INTO fee_events (rider_id, trip_id, amount, event_type, description)
        VALUES (
            NEW.rider_id,
            NEW.id,
            platform_fee_amount,
            'trip_fee',
            'Platform fee for trip ' || NEW.id::TEXT
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_trip_fee
    BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION add_trip_fee();

-- =============================================================================
-- REALTIME SUBSCRIPTIONS
-- =============================================================================

-- Enable realtime for specific tables
ALTER PUBLICATION supabase_realtime ADD TABLE driver_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE trips;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
