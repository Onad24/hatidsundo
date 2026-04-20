-- =============================================================================
-- Admin RPC for Settling Fees
-- Replaces the settle_fees edge function to avoid CORS/JWT issues on web
-- =============================================================================

CREATE OR REPLACE FUNCTION admin_settle_fees(
    p_rider_id UUID,
    p_amount DOUBLE PRECISION,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER -- Runs as DB owner to bypass RLS and ensure updates go through
AS $$
DECLARE
    v_admin_id UUID;
    v_is_admin BOOLEAN;
    
    v_fee RECORD;
    v_remaining_amount DOUBLE PRECISION := p_amount;
    v_fee_outstanding DOUBLE PRECISION;
    v_payment_to_apply DOUBLE PRECISION;
    v_new_paid_amount DOUBLE PRECISION;
    v_is_fully_paid BOOLEAN;
    
    v_settled_count INT := 0;
    v_partial_count INT := 0;
    v_new_outstanding DOUBLE PRECISION;
BEGIN
    -- 1. Verify caller is admin
    v_admin_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM users WHERE id = v_admin_id AND role = 'admin'
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can settle fees';
    END IF;

    -- 2. Verify amount is positive
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero';
    END IF;

    -- 3. Check total outstanding
    SELECT COALESCE(SUM(accrued_fee + due_amount - paid_amount), 0)
    INTO v_new_outstanding
    FROM monthly_fees
    WHERE rider_id = p_rider_id AND is_settled = FALSE;

    IF p_amount > v_new_outstanding THEN
        RAISE EXCEPTION 'Payment amount (₱%) exceeds outstanding balance (₱%)', p_amount, v_new_outstanding;
    END IF;

    -- 4. Apply payments to oldest fees first
    FOR v_fee IN 
        SELECT * FROM monthly_fees 
        WHERE rider_id = p_rider_id AND is_settled = FALSE 
        ORDER BY year ASC, month ASC
    LOOP
        EXIT WHEN v_remaining_amount <= 0;

        v_fee_outstanding := v_fee.accrued_fee + v_fee.due_amount - v_fee.paid_amount;
        
        IF v_remaining_amount >= v_fee_outstanding THEN
            v_payment_to_apply := v_fee_outstanding;
        ELSE
            v_payment_to_apply := v_remaining_amount;
        END IF;

        v_new_paid_amount := v_fee.paid_amount + v_payment_to_apply;
        -- Use an epsilon (0.01) to handle floating point precision issues in Postgres
        v_is_fully_paid := v_new_paid_amount >= ((v_fee.accrued_fee + v_fee.due_amount) - 0.01);

        -- Update the fee record
        UPDATE monthly_fees
        SET 
            paid_amount = v_new_paid_amount,
            is_settled = v_is_fully_paid,
            settled_at = CASE WHEN v_is_fully_paid THEN now() ELSE null END,
            settled_by = CASE WHEN v_is_fully_paid THEN v_admin_id ELSE null END
        WHERE id = v_fee.id;

        IF v_is_fully_paid THEN
            v_settled_count := v_settled_count + 1;
        ELSE
            v_partial_count := v_partial_count + 1;
        END IF;

        v_remaining_amount := v_remaining_amount - v_payment_to_apply;
    END LOOP;

    -- 5. Create fee event for the settlement
    INSERT INTO fee_events (
        rider_id, 
        amount, 
        event_type, 
        description, 
        created_by
    ) VALUES (
        p_rider_id,
        -p_amount, -- Negative because it's a payment
        'settlement',
        COALESCE(p_notes, 'Fee settlement of ₱' || p_amount || ' by admin'),
        v_admin_id
    );

    -- 6. Note: We skip the notifications table insert here as it might depend on push notification triggers,
    -- but if `notifications` is a standard table, we can insert it. Assuming it exists:
    -- INSERT INTO notifications (user_id, type, title, body, payload)
    -- VALUES (p_rider_id, 'payment', 'Fee Settlement', 'A payment of ₱' || p_amount || ' has been applied.', '{}');

    -- Calculate final outstanding
    SELECT COALESCE(SUM(accrued_fee + due_amount - paid_amount), 0)
    INTO v_new_outstanding
    FROM monthly_fees
    WHERE rider_id = p_rider_id AND is_settled = FALSE;

    RETURN json_build_object(
        'success', true,
        'settled_amount', p_amount,
        'settled_fees', v_settled_count,
        'partially_paid_fees', v_partial_count,
        'remaining_outstanding', v_new_outstanding
    );
END;
$$;
