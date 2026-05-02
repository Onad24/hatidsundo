-- Create client locations table
CREATE TABLE client_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id),
    
    -- Location using PostGIS
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_client_locations_client_id ON client_locations(client_id);
CREATE INDEX idx_client_locations_trip_id ON client_locations(trip_id);
CREATE INDEX idx_client_locations_location ON client_locations USING GIST(location);

-- Trigger to update client_locations geography from lat/lng
CREATE OR REPLACE FUNCTION update_client_location_geography()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_client_location_geography
    BEFORE INSERT OR UPDATE OF lat, lng ON client_locations
    FOR EACH ROW EXECUTE FUNCTION update_client_location_geography();

-- Apply update timestamp trigger
CREATE TRIGGER update_client_locations_updated_at
    BEFORE UPDATE ON client_locations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS Policies
ALTER TABLE client_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can insert their own locations"
    ON client_locations FOR INSERT
    WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Clients can update their own locations"
    ON client_locations FOR UPDATE
    USING (auth.uid() = client_id)
    WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Users involved in the trip can view client locations"
    ON client_locations FOR SELECT
    USING (
        auth.uid() = client_id OR
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.id = client_locations.trip_id
            AND (trips.rider_id = auth.uid() OR trips.client_id = auth.uid())
        ) OR
        EXISTS (
            SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
        )
    );
