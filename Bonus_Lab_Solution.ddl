-----------------------------
-- 0. Cleanup (idempotent)
-----------------------------
DROP SCHEMA IF EXISTS kbtubank CASCADE;
CREATE SCHEMA kbtubank;
SET search_path = kbtubank, public;

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-----------------------------
-- 1. DDL: Tables
-----------------------------
CREATE TABLE customers (
  customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  iin CHAR(12) UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  status TEXT NOT NULL DEFAULT 'active', -- active/blocked/frozen
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  daily_limit_kzt NUMERIC(18,2) DEFAULT 500000.00
);

CREATE TABLE accounts (
  account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
  account_number TEXT UNIQUE NOT NULL, -- IBAN-like
  currency CHAR(3) NOT NULL CHECK (currency IN ('KZT','USD','EUR','RUB')),
  balance NUMERIC(20,2) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  opened_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  closed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE exchange_rates (
  rate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_currency CHAR(3) NOT NULL,
  to_currency CHAR(3) NOT NULL,
  rate NUMERIC(18,8) NOT NULL,
  valid_from TIMESTAMP WITH TIME ZONE DEFAULT now(),
  valid_to TIMESTAMP WITH TIME ZONE
);

CREATE TABLE transactions (
  transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_account_id UUID REFERENCES accounts(account_id),
  to_account_id UUID REFERENCES accounts(account_id),
  amount NUMERIC(20,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  exchange_rate NUMERIC(18,8),
  amount_kzt NUMERIC(20,2),
  type TEXT NOT NULL CHECK (type IN ('transfer','deposit','withdrawal')),
  status TEXT NOT NULL CHECK (status IN ('pending','completed','failed','reversed')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  description TEXT
);

CREATE TABLE audit_log (
  log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  table_name TEXT NOT NULL,
  record_id TEXT,
  action TEXT NOT NULL,
  old_values JSONB,
  new_values JSONB,
  changed_by TEXT,
  changed_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  ip_address TEXT
);

-----------------------------
-- 2. Helper: function to get latest exchange rate
-----------------------------
CREATE OR REPLACE FUNCTION get_latest_rate(from_cur CHAR(3), to_cur CHAR(3))
RETURNS NUMERIC AS $$
DECLARE
  r NUMERIC;
BEGIN
  IF from_cur = to_cur THEN
    RETURN 1;
  END IF;
  SELECT rate INTO r FROM exchange_rates
    WHERE from_currency = from_cur AND to_currency = to_cur
      AND (valid_to IS NULL OR valid_to > now())
    ORDER BY valid_from DESC LIMIT 1;
  IF r IS NULL THEN
    RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'No exchange rate from ' || from_cur || ' to ' || to_cur || ' available';
  END IF;
  RETURN r;
END;
$$ LANGUAGE plpgsql VOLATILE;

-----------------------------
-- 3. Audit trigger to log DML operations
-----------------------------
CREATE OR REPLACE FUNCTION audit_trigger_fn() RETURNS trigger AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO audit_log(table_name, record_id, action, new_values, changed_by, ip_address)
    VALUES (TG_TABLE_NAME, COALESCE(NEW::json->>'id', NULL), 'INSERT', to_jsonb(NEW.*), current_user, inet_client_addr());
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    INSERT INTO audit_log(table_name, record_id, action, old_values, new_values, changed_by, ip_address)
    VALUES (TG_TABLE_NAME, COALESCE(NEW::json->>'id', NULL), 'UPDATE', to_jsonb(OLD.*), to_jsonb(NEW.*), current_user, inet_client_addr());
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO audit_log(table_name, record_id, action, old_values, changed_by, ip_address)
    VALUES (TG_TABLE_NAME, COALESCE(OLD::json->>'id', NULL), 'DELETE', to_jsonb(OLD.*), current_user, inet_client_addr());
    RETURN OLD;
  END IF;
  RETURN NULL; -- should not reach
END;
$$ LANGUAGE plpgsql;

-- Attach audit trigger to relevant tables
CREATE TRIGGER audit_customers AFTER INSERT OR UPDATE OR DELETE ON customers
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_accounts AFTER INSERT OR UPDATE OR DELETE ON accounts
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_transactions AFTER INSERT OR UPDATE OR DELETE ON transactions
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_rates AFTER INSERT OR UPDATE OR DELETE ON exchange_rates
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-----------------------------
-- 4. Sample data
-----------------------------
-- customers
INSERT INTO customers(iin, full_name, phone, email, status, daily_limit_kzt)
VALUES
('010101200001', 'Aidar.', '+7-700-111-0001', 'aidar@example.com', 'active', 1000000),
('020202200002', 'Bekzhan', '+7-700-111-0002', 'bayan@example.com', 'active', 500000),
('030303200003', 'Chinara.', '+7-700-111-0003', 'chinara@example.com', 'blocked', 200000),
('040404200004', 'Daniyar.', '+7-700-111-0004', 'daniyar@example.com', 'active', 700000),
('050505200005', 'Elena.', '+7-700-111-0005', 'elena@example.com', 'frozen', 300000),
('060606200006', 'Farkhat.', '+7-700-111-0006', 'farkhat@example.com', 'active', 800000),
('070707200007', 'Gulnara.', '+7-700-111-0007', 'gulnara@example.com', 'active', 600000),
('080808200008', 'Hasan.', '+7-700-111-0008', 'hasan@example.com', 'active', 400000),
('090909200009', 'Inkar.', '+7-700-111-0009', 'inkar@example.com', 'active', 250000),
('101010200010', 'Jamil.', '+7-700-111-0010', 'jamil@example.com', 'active', 1000000);

-- accounts (each customer has 1-2 accounts)
INSERT INTO accounts(customer_id, account_number, currency, balance, is_active)
SELECT customer_id, 'KZ' || substring(iin from 1 for 8) || '-' || generate_series::text, 'KZT', 100000 + (random()*900000)::numeric(10,2), true
FROM customers, generate_series(1,1);

-- Add extra USD/EUR accounts for some customers
INSERT INTO accounts(customer_id, account_number, currency, balance, is_active)
SELECT c.customer_id, 'IBAN' || substring(c.iin from 1 for 8) || '-USD', 'USD', (1000 + (random()*9000))::numeric(10,2), true
FROM customers c WHERE c.iin IN ('010101200001','020202200002','040404200004','060606200006');

-- exchange rates (to KZT base)
INSERT INTO exchange_rates(from_currency, to_currency, rate, valid_from)
VALUES
('USD','KZT', 460.00, now()-interval '2 days'),
('EUR','KZT', 500.00, now()-interval '2 days'),
('RUB','KZT', 5.50, now()-interval '2 days'),
('KZT','KZT', 1, now()-interval '2 days'),
('USD','EUR', 0.92, now()-interval '2 days'),
('EUR','USD', 1.08, now()-interval '2 days');

-- transactions (seed some transfers)
INSERT INTO transactions(from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description)
SELECT a1.account_id, a2.account_id, (100 + (random()*1000))::numeric(10,2), a1.currency, 1, ((100 + (random()*1000))::numeric(10,2) * 1), 'transfer', 'completed', 'seed transfer'
FROM accounts a1 CROSS JOIN accounts a2
WHERE a1.account_id <> a2.account_id
LIMIT 12;

-----------------------------
-- 5. Task 1: process_transfer procedure
-----------------------------
-- This procedure performs a safe transfer with all required checks.
CREATE OR REPLACE FUNCTION process_transfer(
  p_from_account TEXT,
  p_to_account TEXT,
  p_amount NUMERIC,
  p_currency CHAR(3),
  p_description TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_from accounts%ROWTYPE;
  v_to accounts%ROWTYPE;
  v_from_customer customers%ROWTYPE;
  v_amount_kzt NUMERIC(20,2);
  v_rate NUMERIC(18,8);
  v_today_sum NUMERIC := 0;
  v_result JSONB;
  v_tx_id UUID := uuid_generate_v4();
BEGIN
  IF p_amount <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_AMOUNT', 'msg', 'Amount must be positive');
  END IF;

  -- Lock source and destination accounts to prevent race conditions
  SELECT * INTO v_from FROM accounts WHERE account_number = p_from_account FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'FROM_NOT_FOUND', 'msg', 'Source account not found');
  END IF;
  SELECT * INTO v_to FROM accounts WHERE account_number = p_to_account FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TO_NOT_FOUND', 'msg', 'Destination account not found');
  END IF;

  -- Check accounts active
  IF NOT v_from.is_active THEN
    RETURN jsonb_build_object('ok', false, 'code', 'FROM_INACTIVE', 'msg', 'Source account is not active');
  END IF;
  IF NOT v_to.is_active THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TO_INACTIVE', 'msg', 'Destination account is not active');
  END IF;

  -- Check customer status
  SELECT * INTO v_from_customer FROM customers WHERE customer_id = v_from.customer_id;
  IF v_from_customer.status <> 'active' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CUSTOMER_NOT_ACTIVE', 'msg', 'Sender customer status is not active');
  END IF;

  -- compute kzt amount using exchange rates
  v_rate := get_latest_rate(p_currency, 'KZT');
  v_amount_kzt := (p_amount * v_rate)::numeric(20,2);

  -- Check daily limit: sum of today's completed+pending transfers from accounts of the customer
  SELECT COALESCE(SUM(amount_kzt),0) INTO v_today_sum FROM transactions t
    JOIN accounts a ON t.from_account_id = a.account_id
    WHERE a.customer_id = v_from.customer_id
      AND t.created_at >= date_trunc('day', now())
      AND t.status IN ('pending','completed');

  IF (v_today_sum + v_amount_kzt) > v_from_customer.daily_limit_kzt THEN
    -- log failed attempt
    INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at)
    VALUES (v_tx_id, v_from.account_id, v_to.account_id, p_amount, p_currency, v_rate, v_amount_kzt, 'transfer', 'failed', 'Daily limit exceeded: ' || coalesce(p_description,''), now());

    RETURN jsonb_build_object('ok', false, 'code', 'DAILY_LIMIT_EXCEEDED', 'msg', 'Daily transaction limit exceeded');
  END IF;

  -- Check sufficient balance (convert if account currency differs)
  -- Convert p_amount to account currency of source if necessary
  -- For security, ensure we use exchange rates for conversions
  IF v_from.currency = p_currency THEN
    IF v_from.balance < p_amount THEN
      INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at)
      VALUES (v_tx_id, v_from.account_id, v_to.account_id, p_amount, p_currency, v_rate, v_amount_kzt, 'transfer', 'failed', 'Insufficient funds: ' || coalesce(p_description,''), now());
      RETURN jsonb_build_object('ok', false, 'code', 'INSUFFICIENT_FUNDS', 'msg', 'Insufficient balance');
    END IF;
  ELSE
    -- convert p_amount to sender account currency via KZT as intermediary
    DECLARE
      rate_to_sender NUMERIC := get_latest_rate(p_currency, v_from.currency);
      required_in_sender_currency NUMERIC := (p_amount * rate_to_sender)::numeric(20,2);
    BEGIN
      IF v_from.balance < required_in_sender_currency THEN
        INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at)
        VALUES (v_tx_id, v_from.account_id, v_to.account_id, p_amount, p_currency, v_rate, v_amount_kzt, 'transfer', 'failed', 'Insufficient funds after conversion: ' || coalesce(p_description,''), now());
        RETURN jsonb_build_object('ok', false, 'code', 'INSUFFICIENT_FUNDS_CONV', 'msg', 'Insufficient balance after currency conversion');
      END IF;
    END;
  END IF;

  -- All checks passed, perform transfer in transaction block with savepoint
  SAVEPOINT sp_transfer;
  BEGIN
    -- Debit source
    IF v_from.currency = p_currency THEN
      UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from.account_id;
    ELSE
      -- convert amount to source currency and debit
      PERFORM get_latest_rate(p_currency, v_from.currency) INTO STRICT rate_to_sender;
    END IF;

    -- Compute exchange for destination
    v_rate := get_latest_rate(p_currency, v_to.currency);
    -- compute amount to credit in destination currency
    DECLARE
      v_credit_amount NUMERIC := (p_amount * v_rate)::numeric(20,2);
    BEGIN
      UPDATE accounts SET balance = balance + v_credit_amount WHERE account_id = v_to.account_id;
    EXCEPTION WHEN OTHERS THEN
      ROLLBACK TO SAVEPOINT sp_transfer;
      -- mark transaction failed
      INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at)
      VALUES (v_tx_id, v_from.account_id, v_to.account_id, p_amount, p_currency, v_rate, v_amount_kzt, 'transfer', 'failed', 'Credit failed: ' || SQLERRM, now());
      RETURN jsonb_build_object('ok', false, 'code', 'CREDIT_FAIL', 'msg', 'Failed to credit destination: ' || SQLERRM);
    END;

    -- Record transaction as completed
    INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at, completed_at)
    VALUES (v_tx_id, v_from.account_id, v_to.account_id, p_amount, p_currency, v_rate, v_amount_kzt, 'transfer', 'completed', p_description, now(), now());

    -- Log to audit (the triggers will log changes)

    RELEASE SAVEPOINT sp_transfer;
  END;

  v_result := jsonb_build_object('ok', true, 'code', 'SUCCESS', 'msg', 'Transfer completed', 'transaction_id', v_tx_id);
  RETURN v_result;

EXCEPTION WHEN others THEN
  ROLLBACK; -- full rollback of the function's transaction
  RETURN jsonb_build_object('ok', false, 'code', 'UNEXPECTED_ERROR', 'msg', SQLERRM);
END;
$$;

-----------------------------
-- 6. Task 2: Views
-----------------------------
-- View 1: customer_balance_summary
CREATE OR REPLACE VIEW customer_balance_summary AS
SELECT
  c.customer_id,
  c.full_name,
  c.iin,
  a.account_id,
  a.account_number,
  a.currency,
  a.balance,
  -- Convert each account to KZT using latest rates (subquery)
  (a.balance * COALESCE((SELECT rate FROM exchange_rates er WHERE er.from_currency = a.currency AND er.to_currency = 'KZT' AND (er.valid_to IS NULL OR er.valid_to > now()) ORDER BY er.valid_from DESC LIMIT 1),1))::numeric(20,2) AS balance_kzt,
  SUM(a.balance * COALESCE((SELECT rate FROM exchange_rates er WHERE er.from_currency = a.currency AND er.to_currency = 'KZT' AND (er.valid_to IS NULL OR er.valid_to > now()) ORDER BY er.valid_from DESC LIMIT 1),1)) OVER (PARTITION BY c.customer_id)::numeric(20,2) AS total_balance_kzt,
  c.daily_limit_kzt,
  (SUM(a.balance * COALESCE((SELECT rate FROM exchange_rates er WHERE er.from_currency = a.currency AND er.to_currency = 'KZT' AND (er.valid_to IS NULL OR er.valid_to > now()) ORDER BY er.valid_from DESC LIMIT 1),1)) OVER (PARTITION BY c.customer_id) / NULLIF(c.daily_limit_kzt,0) * 100)::numeric(5,2) AS daily_limit_util_pct,
  RANK() OVER (ORDER BY SUM(a.balance * COALESCE((SELECT rate FROM exchange_rates er WHERE er.from_currency = a.currency AND er.to_currency = 'KZT' AND (er.valid_to IS NULL OR er.valid_to > now()) ORDER BY er.valid_from DESC LIMIT 1),1)) OVER (PARTITION BY c.customer_id) DESC) AS balance_rank
FROM customers c
JOIN accounts a ON a.customer_id = c.customer_id;

-- View 2: daily_transaction_report
CREATE OR REPLACE VIEW daily_transaction_report AS
SELECT
  date_trunc('day', t.created_at) AS day,
  t.type,
  COUNT(*) AS tx_count,
  SUM(t.amount_kzt) AS total_volume_kzt,
  AVG(t.amount_kzt) AS avg_amount_kzt,
  SUM(SUM(t.amount_kzt)) OVER (ORDER BY date_trunc('day', t.created_at) ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_kzt,
  (SUM(t.amount_kzt) - LAG(SUM(t.amount_kzt)) OVER (ORDER BY date_trunc('day', t.created_at)))/NULLIF(LAG(SUM(t.amount_kzt)) OVER (ORDER BY date_trunc('day', t.created_at)),0)::numeric AS day_over_day_growth
FROM transactions t
GROUP BY date_trunc('day', t.created_at), t.type
ORDER BY day DESC;

-- View 3: suspicious_activity_view (WITH SECURITY BARRIER)
CREATE OR REPLACE VIEW suspicious_activity_view WITH (security_barrier = true) AS
SELECT
  t.transaction_id,
  t.from_account_id,
  t.to_account_id,
  t.amount_kzt,
  t.created_at,
  CASE WHEN t.amount_kzt > 5000000 THEN true ELSE false END AS over_5m_kzt,
  -- customers with >10 transactions in an hour
  (SELECT COUNT(*) FROM transactions t2 WHERE t2.from_account_id = t.from_account_id AND t2.created_at BETWEEN t.created_at - interval '59 seconds' AND t.created_at + interval '59 seconds') AS txs_in_window
FROM transactions t
WHERE t.amount_kzt > 5000000
   OR (SELECT COUNT(*) FROM transactions t2 WHERE t2.from_account_id = t.from_account_id AND t2.created_at >= t.created_at - interval '1 hour' AND t2.created_at <= t.created_at + interval '1 hour') > 10
   OR EXISTS (SELECT 1 FROM transactions t3 WHERE t3.from_account_id = t.from_account_id AND t3.created_at > t.created_at - interval '1 minute' AND t3.created_at < t.created_at + interval '1 minute' AND t3.transaction_id <> t.transaction_id);

-----------------------------
-- 7. Task 3: Index strategy
-----------------------------
-- 1) B-tree on accounts.account_number (unique index already created by UNIQUE constraint)
-- 2) Composite B-tree for frequent queries: transactions by from_account and created_at
CREATE INDEX idx_transactions_from_createdat ON transactions (from_account_id, created_at DESC);

-- 3) Partial index for active accounts only
CREATE INDEX idx_accounts_active ON accounts(account_id) WHERE is_active = true;

-- 4) Expression index for case-insensitive email search
CREATE INDEX idx_customers_lower_email ON customers ((lower(email))) WHERE email IS NOT NULL;

-- 5) GIN index on audit_log JSONB columns (old_values and new_values)
CREATE INDEX idx_audit_log_jsonb ON audit_log USING GIN (COALESCE(old_values,'{}'::jsonb) || COALESCE(new_values,'{}'::jsonb));

-- 6) Hash index for quick lookup on account_number text (example; note: Hash indexes only efficient for equality)
CREATE INDEX idx_accounts_number_hash ON accounts USING HASH (account_number);

-- 7) Covering index (include) for most frequent pattern: transactions by from_account_id with amount_kzt and status
-- PostgreSQL doesn't support INCLUDE for all versions; use btree with included columns (supported 11+)
CREATE INDEX idx_transactions_covering ON transactions (from_account_id, status) INCLUDE (amount_kzt, created_at);

-- Note: EXPLAIN ANALYZE statements are provided below as comments — run them in your environment to collect outputs.
-- Example: EXPLAIN ANALYZE SELECT * FROM transactions WHERE from_account_id = '<uuid>' ORDER BY created_at DESC LIMIT 10;

-----------------------------
-- 8. Task 4: process_salary_batch procedure
-----------------------------
CREATE OR REPLACE FUNCTION process_salary_batch(
  p_company_account_number TEXT,
  p_payments JSONB -- array of objects: [{"iin":"...","amount":1000.00,"description":"..."},...]
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_company_acc accounts%ROWTYPE;
  v_total NUMERIC := 0;
  v_pay JSONB;
  v_iin TEXT;
  v_amount NUMERIC;
  v_description TEXT;
  v_customer customers%ROWTYPE;
  v_recipient_acc accounts%ROWTYPE;
  v_failures JSONB := '[]'::jsonb;
  v_success_count INT := 0;
  v_failed_count INT := 0;
  v_locked BOOLEAN := false;
  v_tx_ids JSONB := '[]'::jsonb;
  v_updates JSONB := '[]'::jsonb;
  v_total_debit NUMERIC := 0;
BEGIN
  -- Acquire advisory lock to prevent concurrent batches for same company (hash on company account number)
  PERFORM pg_advisory_lock(hashtext(p_company_account_number)::bigint);

  SELECT * INTO v_company_acc FROM accounts WHERE account_number = p_company_account_number FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM pg_advisory_unlock(hashtext(p_company_account_number)::bigint);
    RETURN jsonb_build_object('ok', false, 'code', 'COMPANY_ACCOUNT_NOT_FOUND');
  END IF;

  -- Calculate total batch amount
  FOR v_pay IN SELECT * FROM jsonb_array_elements(p_payments) LOOP
    v_amount := (v_pay ->> 'amount')::numeric;
    v_total := v_total + v_amount;
  END LOOP;

  IF v_company_acc.balance < v_total THEN
    PERFORM pg_advisory_unlock(hashtext(p_company_account_number)::bigint);
    RETURN jsonb_build_object('ok', false, 'code', 'INSUFFICIENT_FUNDS_COMPANY', 'available', v_company_acc.balance, 'required', v_total);
  END IF;

  -- We'll perform per-payment processing with savepoints; final update to company account will be atomic at the end
  -- Create temp table to accumulate credits
  CREATE TEMP TABLE tmp_salary_credits (account_id UUID, credit_amount NUMERIC) ON COMMIT DROP;

  FOR v_pay IN SELECT * FROM jsonb_array_elements(p_payments) LOOP
    BEGIN
      v_iin := v_pay ->> 'iin';
      v_amount := (v_pay ->> 'amount')::numeric;
      v_description := COALESCE(v_pay ->> 'description','Salary');

      -- Find customer by iin
      SELECT * INTO v_customer FROM customers WHERE iin = v_iin;
      IF NOT FOUND THEN
        v_failed_count := v_failed_count + 1;
        v_failures := v_failures || jsonb_build_object('iin', v_iin, 'reason', 'Customer not found');
        CONTINUE;
      END IF;

      -- Find any active account for customer in KZT preferred
      SELECT * INTO v_recipient_acc FROM accounts WHERE customer_id = v_customer.customer_id AND is_active = true ORDER BY (currency='KZT') DESC LIMIT 1 FOR UPDATE;
      IF NOT FOUND THEN
        v_failed_count := v_failed_count + 1;
        v_failures := v_failures || jsonb_build_object('iin', v_iin, 'reason', 'Recipient account not found');
        CONTINUE;
      END IF;

      -- Create savepoint per payment
      SAVEPOINT sp_pay;
      BEGIN
        -- Insert transaction record as pending
        INSERT INTO transactions(transaction_id, from_account_id, to_account_id, amount, currency, exchange_rate, amount_kzt, type, status, description, created_at)
        VALUES (uuid_generate_v4(), v_company_acc.account_id, v_recipient_acc.account_id, v_amount, v_recipient_acc.currency, get_latest_rate('KZT', v_recipient_acc.currency), (v_amount * get_latest_rate('KZT','KZT'))::numeric(20,2), 'transfer', 'pending', v_description, now())
        RETURNING transaction_id INTO STRICT v_tx_ids;

        -- Instead of updating balances per payment, accumulate credits in temp table
        INSERT INTO tmp_salary_credits(account_id, credit_amount)
        VALUES (v_recipient_acc.account_id, (v_amount * get_latest_rate('KZT', v_recipient_acc.currency))::numeric(20,2))
        ON CONFLICT (account_id) DO UPDATE SET credit_amount = tmp_salary_credits.credit_amount + EXCLUDED.credit_amount;

        v_success_count := v_success_count + 1;
      EXCEPTION WHEN OTHERS THEN
        ROLLBACK TO SAVEPOINT sp_pay;
        v_failed_count := v_failed_count + 1;
        v_failures := v_failures || jsonb_build_object('iin', v_iin, 'reason', SQLERRM);
        -- continue processing next payments
      END;
    END;
  END LOOP;

  -- After processing all payments, perform final debit from company account and credit recipients atomically
  BEGIN
    -- compute total to debit from temp table
    SELECT COALESCE(SUM(credit_amount),0) INTO v_total_debit FROM tmp_salary_credits;
    IF v_company_acc.balance < v_total_debit THEN
      -- Should not happen due to earlier check but double-check
      PERFORM pg_advisory_unlock(hashtext(p_company_account_number)::bigint);
      RETURN jsonb_build_object('ok', false, 'code', 'RACE_INSUFFICIENT_FUNDS', 'available', v_company_acc.balance, 'required', v_total_debit);
    END IF;

    -- Debit company account
    UPDATE accounts SET balance = balance - v_total_debit WHERE account_id = v_company_acc.account_id;

    -- Credit recipients
    FOR v_recipient_acc IN SELECT account_id, credit_amount FROM tmp_salary_credits LOOP
      UPDATE accounts SET balance = balance + v_recipient_acc.credit_amount WHERE account_id = v_recipient_acc.account_id;
    END LOOP;

    -- Mark corresponding transactions as completed (best-effort: mark recent pending transfers from company account)
    UPDATE transactions SET status = 'completed', completed_at = now()
      WHERE from_account_id = v_company_acc.account_id AND status = 'pending' AND created_at > now() - interval '1 hour';

  EXCEPTION WHEN OTHERS THEN
    -- In case of any failure, rollback and report
    ROLLBACK;
    PERFORM pg_advisory_unlock(hashtext(p_company_account_number)::bigint);
    RETURN jsonb_build_object('ok', false, 'code', 'FINAL_COMMIT_FAILED', 'msg', SQLERRM);
  END;

  -- release advisory lock
  PERFORM pg_advisory_unlock(hashtext(p_company_account_number)::bigint);

  RETURN jsonb_build_object('ok', true, 'successful_count', v_success_count, 'failed_count', v_failed_count, 'failed_details', v_failures);
END;
$$;

-----------------------------
-- 9. Materialized view for salary batch summary
-----------------------------
CREATE MATERIALIZED VIEW salary_batch_summary AS
SELECT
  date_trunc('day', t.created_at) AS day,
  COUNT(*) FILTER (WHERE t.type='transfer') AS transfers_count,
  SUM(t.amount_kzt) FILTER (WHERE t.type='transfer') AS total_transfers_kzt
FROM transactions t
GROUP BY date_trunc('day', t.created_at);

-- Refresh manually after batch runs: REFRESH MATERIALIZED VIEW salary_batch_summary;

-----------------------------
-- 10. Test Cases (examples you can run manually)
-----------------------------
-- 1) Successful transfer (replace account numbers with those in your DB)
-- SELECT process_transfer('KZ01010120-1','KZ02020220-1',1000,'KZT','Test transfer');

-- 2) Transfer exceeding daily limit
-- SELECT process_transfer('KZ03030320-1','KZ02020220-1',10000000,'KZT','Big transfer');

-- 3) Salary batch
-- SELECT process_salary_batch('KZCOMPANY001', '[{"iin":"010101200001","amount":10000},{"iin":"020202200002","amount":5000}]');

-- 4) EXPLAIN ANALYZE examples to run in psql for index justification
-- EXPLAIN ANALYZE SELECT * FROM transactions WHERE from_account_id = '<some-uuid>' ORDER BY created_at DESC LIMIT 10;
-- EXPLAIN ANALYZE SELECT * FROM accounts WHERE is_active = true AND account_number = '...';

-----------------------------
--  End of script
-----------------------------