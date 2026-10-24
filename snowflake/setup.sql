-- Liftr: Snowflake setup.
-- Paste this whole file into a Snowsight SQL worksheet, select everything (Ctrl/Cmd + A), and Run.
-- Safe to run more than once. The LAST result shows the backend's token in the token_secret column.
-- Copy it right away into backend/.env as SNOWFLAKE_PAT. Snowflake shows it only once.

USE ROLE ACCOUNTADMIN;

-- 1. Compute, database and schema
CREATE WAREHOUSE IF NOT EXISTS LIFTR_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE LIFTR_WH;
CREATE DATABASE IF NOT EXISTS LIFTR;
CREATE SCHEMA IF NOT EXISTS LIFTR.APP;
USE SCHEMA LIFTR.APP;

-- 2. A role with only what the backend needs
CREATE ROLE IF NOT EXISTS LIFTR_APP_ROLE;
GRANT ROLE LIFTR_APP_ROLE TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE LIFTR_WH TO ROLE LIFTR_APP_ROLE;
GRANT USAGE ON DATABASE LIFTR TO ROLE LIFTR_APP_ROLE;
GRANT USAGE ON SCHEMA LIFTR.APP TO ROLE LIFTR_APP_ROLE;

-- 3. Daily logs. Mirrors DailyLog in the iOS app: one row per user, day and product.
-- Logging the same day and product again overwrites it, like the app does.
CREATE TABLE IF NOT EXISTS daily_logs (
  user_id       STRING NOT NULL,     -- random ID the app creates on first launch
  day_key       DATE   NOT NULL,     -- the user's calendar day (the app's "yyyy-MM-dd" dayKey)
  product_type  STRING NOT NULL DEFAULT 'cigarette',  -- cigarette | vape | pouch | cigar | gum | other
  quantity      FLOAT  NOT NULL,     -- cigarettes, puffs, pouches...; 0 = nicotine-free day
  unit          STRING NOT NULL DEFAULT 'cigarette',
  craving_level NUMBER(2),           -- 0 (none) to 10 (overwhelming)
  mood          STRING,
  note          STRING,
  source        STRING,              -- 'voice' or 'manual'
  updated_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (user_id, day_key, product_type)   -- recorded, not enforced; the backend MERGEs on it
);

-- 4. One row per user and day, all products added up
CREATE OR REPLACE VIEW daily_totals AS
SELECT user_id, day_key,
       SUM(IFF(product_type = 'cigarette', quantity, 0)) AS cigarettes,
       SUM(quantity)                                     AS total_units,
       MAX(craving_level)                                AS max_craving,
       ANY_VALUE(mood)                                   AS mood
FROM daily_logs
GROUP BY user_id, day_key;

-- 5. Voice check-in transcripts from the Coach tab: one row per call, the whole conversation in `transcript`.
-- The app sends a call again until it's saved, so the backend MERGEs on (user_id, conversation_id).
CREATE TABLE IF NOT EXISTS conversations (
  user_id         STRING NOT NULL,
  conversation_id STRING NOT NULL,   -- random ID the app gives each call
  channel         STRING NOT NULL DEFAULT 'voice',
  started_at      TIMESTAMP_TZ,
  ended_at        TIMESTAMP_TZ,
  message_count   NUMBER,
  logged_summary  STRING,            -- what the agent logged, e.g. 'Today logged as sober'
  transcript      VARIANT,           -- [{"role": "user" | "assistant", "text": "..."}]
  updated_at      TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (user_id, conversation_id)   -- recorded, not enforced
);

-- 6. Let the backend's role read and write
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA LIFTR.APP TO ROLE LIFTR_APP_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA LIFTR.APP TO ROLE LIFTR_APP_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA LIFTR.APP TO ROLE LIFTR_APP_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA LIFTR.APP TO ROLE LIFTR_APP_ROLE;

-- 7. A login for the backend (not for a person)
CREATE USER IF NOT EXISTS LIFTR_BACKEND
  TYPE = SERVICE DEFAULT_ROLE = LIFTR_APP_ROLE DEFAULT_WAREHOUSE = LIFTR_WH;
GRANT ROLE LIFTR_APP_ROLE TO USER LIFTR_BACKEND;

-- Tokens only work for a user with a network policy. 0.0.0.0/0 allows any IP:
-- fine for a hackathon, tighten it afterwards.
CREATE NETWORK POLICY IF NOT EXISTS LIFTR_BACKEND_POLICY ALLOWED_IP_LIST = ('0.0.0.0/0');
ALTER USER LIFTR_BACKEND SET NETWORK_POLICY = LIFTR_BACKEND_POLICY;

-- 8. The token, shown ONCE in the token_secret column.
-- Running the file again makes this line fail because the token exists. That's fine; the old one still works.
-- For a fresh one, first run: ALTER USER LIFTR_BACKEND REMOVE PROGRAMMATIC ACCESS TOKEN liftr_backend_token;
ALTER USER LIFTR_BACKEND ADD PROGRAMMATIC ACCESS TOKEN liftr_backend_token
  ROLE_RESTRICTION = 'LIFTR_APP_ROLE' DAYS_TO_EXPIRY = 60;
