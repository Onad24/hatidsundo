-- =============================================================================
-- Migration: Convert fee settlement from monthly to weekly
-- =============================================================================

-- 1. Add week column to monthly_fees
ALTER TABLE monthly_fees ADD COLUMN IF NOT EXISTS week INTEGER;

-- 2. Populate existing rows with ISO week number from created_at
UPDATE monthly_fees SET week = EXTRACT(WEEK FROM created_at) WHERE week IS NULL;

-- 3. Set default for future inserts
ALTER TABLE monthly_fees ALTER COLUMN week SET DEFAULT 1;
ALTER TABLE monthly_fees ALTER COLUMN week SET NOT NULL;

-- 4. Drop old unique constraint (rider_id, year, month) and add new one (rider_id, year, week)
ALTER TABLE monthly_fees DROP CONSTRAINT IF EXISTS monthly_fees_rider_id_year_month_key;
ALTER TABLE monthly_fees ADD CONSTRAINT monthly_fees_rider_id_year_week_key UNIQUE (rider_id, year, week);

-- 5. Update the add_trip_fee trigger to key by ISO week instead of month
CREATE OR REPLACE FUNCTION add_trip_fee()
RETURNS TRIGGER AS $$
DECLARE
    platform_fee_amount DECIMAL(10, 2);
    current_year INTEGER;
    current_week INTEGER;
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Calculate platform fee (10%)
        platform_fee_amount := COALESCE(NEW.fare_final, NEW.fare_estimated) * 0.10;
        NEW.platform_fee := platform_fee_amount;

        current_year := EXTRACT(YEAR FROM NOW());
        current_week := EXTRACT(WEEK FROM NOW());

        -- Upsert weekly fee record
        INSERT INTO monthly_fees (rider_id, year, month, week, accrued_fee)
        VALUES (NEW.rider_id, current_year, EXTRACT(MONTH FROM NOW()), current_week, platform_fee_amount)
        ON CONFLICT (rider_id, year, week)
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

-- 6. Update rollover function to work weekly
CREATE OR REPLACE FUNCTION rollover_weekly_fees()
RETURNS void AS $$
DECLARE
    current_year INTEGER;
    current_week INTEGER;
    prev_year INTEGER;
    prev_week INTEGER;
BEGIN
    current_year := EXTRACT(YEAR FROM NOW());
    current_week := EXTRACT(WEEK FROM NOW());

    -- Calculate previous week
    IF current_week = 1 THEN
        prev_year := current_year - 1;
        prev_week := 52;
    ELSE
        prev_year := current_year;
        prev_week := current_week - 1;
    END IF;

    -- Rollover unsettled fees from previous week
    UPDATE monthly_fees
    SET
        rolled_over_at = NOW(),
        updated_at = NOW()
    WHERE year = prev_year
      AND week = prev_week
      AND is_settled = false
      AND rolled_over_at IS NULL;

    -- Add due amount to new week records
    INSERT INTO monthly_fees (rider_id, year, month, week, due_amount)
    SELECT
        rider_id,
        current_year,
        EXTRACT(MONTH FROM NOW()),
        current_week,
        (accrued_fee + due_amount - paid_amount)
    FROM monthly_fees
    WHERE year = prev_year
      AND week = prev_week
      AND is_settled = false
      AND (accrued_fee + due_amount - paid_amount) > 0
    ON CONFLICT (rider_id, year, week)
    DO UPDATE SET
        due_amount = monthly_fees.due_amount + EXCLUDED.due_amount,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- 7. Update the fee statistics RPC to support weekly
CREATE OR REPLACE FUNCTION get_weekly_fee_statistics(p_year INT, p_week INT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_accrued DOUBLE PRECISION;
    v_total_collected DOUBLE PRECISION;
    v_outstanding_balance DOUBLE PRECISION;
    v_collection_rate DOUBLE PRECISION;
BEGIN
    SELECT
        COALESCE(SUM(accrued_fee), 0),
        COALESCE(SUM(paid_amount), 0),
        COALESCE(SUM(accrued_fee + due_amount - paid_amount), 0)
    INTO
        v_total_accrued,
        v_total_collected,
        v_outstanding_balance
    FROM monthly_fees
    WHERE year = p_year AND week = p_week;

    IF v_total_accrued > 0 THEN
        v_collection_rate := (v_total_collected / (v_total_accrued + v_outstanding_balance)) * 100;
    ELSE
        v_collection_rate := 0;
    END IF;

    RETURN json_build_object(
        'total_accrued', v_total_accrued,
        'total_collected', v_total_collected,
        'outstanding_balance', v_outstanding_balance,
        'collection_rate', v_collection_rate
    );
END;
$$;
