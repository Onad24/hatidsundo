-- Remote Procedure Call (RPC) definitions for Fee Management

-- 1. Get total outstanding dues for a rider
CREATE OR REPLACE FUNCTION get_total_outstanding_dues(p_rider_id UUID)
RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total DOUBLE PRECISION;
BEGIN
    SELECT COALESCE(SUM(accrued_fee + due_amount - paid_amount), 0)
    INTO total
    FROM monthly_fees
    WHERE rider_id = p_rider_id
      AND is_settled = FALSE;
    
    RETURN total;
END;
$$;

-- 2. Add fee adjustment (creates or updates monthly fee record)
CREATE OR REPLACE FUNCTION add_fee_adjustment(
    p_rider_id UUID,
    p_year INT,
    p_month INT,
    p_amount DOUBLE PRECISION
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Try to update existing record
    UPDATE monthly_fees
    SET due_amount = due_amount + p_amount
    WHERE rider_id = p_rider_id
      AND year = p_year
      AND month = p_month;

    -- If no record updated, insert a new one
    IF NOT FOUND THEN
        INSERT INTO monthly_fees (
            rider_id,
            year,
            month,
            accrued_fee,
            due_amount,
            paid_amount,
            is_settled
        ) VALUES (
            p_rider_id,
            p_year,
            p_month,
            0, -- accrued fee starts at 0 if just an adjustment
            p_amount,
            0,
            FALSE
        );
    END IF;
END;
$$;

-- 3. Get all riders with outstanding dues
CREATE OR REPLACE FUNCTION get_riders_with_outstanding_dues()
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    phone_number TEXT,
    total_outstanding DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id AS user_id,
        u.name,
        u.email,
        u.phone_number,
        COALESCE(SUM(mf.accrued_fee + mf.due_amount - mf.paid_amount), 0) AS total_outstanding
    FROM rider_profiles rp
    JOIN users u ON rp.user_id = u.id
    JOIN monthly_fees mf ON rp.user_id = mf.rider_id
    WHERE mf.is_settled = FALSE
    GROUP BY u.id, u.name, u.email, u.phone_number
    HAVING COALESCE(SUM(mf.accrued_fee + mf.due_amount - mf.paid_amount), 0) > 0;
END;
$$;

-- 4. Get monthly fee statistics
CREATE OR REPLACE FUNCTION get_monthly_fee_statistics(p_month TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_year INT;
    v_month INT;
    v_total_accrued DOUBLE PRECISION;
    v_total_collected DOUBLE PRECISION;
    v_outstanding_balance DOUBLE PRECISION;
    v_collection_rate DOUBLE PRECISION;
BEGIN
    -- Parse YYYY-MM string
    v_year := CAST(SPLIT_PART(p_month, '-', 1) AS INT);
    v_month := CAST(SPLIT_PART(p_month, '-', 2) AS INT);

    -- Calculate stats
    SELECT 
        COALESCE(SUM(accrued_fee), 0),
        COALESCE(SUM(paid_amount), 0),
        COALESCE(SUM(accrued_fee + due_amount - paid_amount), 0)
    INTO 
        v_total_accrued,
        v_total_collected,
        v_outstanding_balance
    FROM monthly_fees
    WHERE year = v_year AND month = v_month;

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

-- 5. Export fee data
CREATE OR REPLACE FUNCTION export_fee_data(start_month TEXT, end_month TEXT)
RETURNS TEXT -- Returns CSV string
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_year INT;
    v_start_month INT;
    v_end_year INT;
    v_end_month INT;
    v_csv TEXT := 'Rider Name,Email,Period,Accrued Fee,Adjustments/Due,Paid Amount,Status,Outstanding\n';
    v_rec RECORD;
BEGIN
    -- Parse inputs
    v_start_year := CAST(SPLIT_PART(start_month, '-', 1) AS INT);
    v_start_month := CAST(SPLIT_PART(start_month, '-', 2) AS INT);
    v_end_year := CAST(SPLIT_PART(end_month, '-', 1) AS INT);
    v_end_month := CAST(SPLIT_PART(end_month, '-', 2) AS INT);

    FOR v_rec IN
        SELECT 
            u.name,
            u.email,
            mf.year || '-' || LPAD(mf.month::TEXT, 2, '0') AS period,
            mf.accrued_fee,
            mf.due_amount,
            mf.paid_amount,
            CASE WHEN mf.is_settled THEN 'Settled' ELSE 'Pending' END AS status,
            (mf.accrued_fee + mf.due_amount - mf.paid_amount) AS outstanding
        FROM monthly_fees mf
        JOIN users u ON mf.rider_id = u.id
        WHERE 
            (mf.year > v_start_year OR (mf.year = v_start_year AND mf.month >= v_start_month))
            AND (mf.year < v_end_year OR (mf.year = v_end_year AND mf.month <= v_end_month))
        ORDER BY mf.year DESC, mf.month DESC, u.name ASC
    LOOP
        v_csv := v_csv || 
                 '"' || v_rec.name || '",' ||
                 v_rec.email || ',' ||
                 v_rec.period || ',' ||
                 v_rec.accrued_fee || ',' ||
                 v_rec.due_amount || ',' ||
                 v_rec.paid_amount || ',' ||
                 v_rec.status || ',' ||
                 v_rec.outstanding || E'\n';
    END LOOP;

    RETURN v_csv;
END;
$$;
