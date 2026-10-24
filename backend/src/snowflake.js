import snowflake from "snowflake-sdk";

snowflake.configure({ logLevel: "WARN" });

let connection = null;

function connect() {
  const c = snowflake.createConnection({
    account: process.env.SNOWFLAKE_ACCOUNT,
    username: process.env.SNOWFLAKE_USER,
    // A programmatic access token goes in the password field.
    password: process.env.SNOWFLAKE_PAT,
    role: process.env.SNOWFLAKE_ROLE,
    warehouse: process.env.SNOWFLAKE_WAREHOUSE,
    database: process.env.SNOWFLAKE_DATABASE ?? "LIFTR",
    schema: process.env.SNOWFLAKE_SCHEMA ?? "APP",
    clientSessionKeepAlive: true,
  });
  return new Promise((resolve, reject) =>
    c.connect((err) => (err ? reject(err) : resolve(c)))
  );
}

async function getConnection() {
  if (connection?.isUp()) return connection;
  connection = await connect();
  return connection;
}

/** Runs one SQL statement. Pass user input only through `binds` (the ? marks), never by pasting it into `sqlText`. */
export async function query(sqlText, binds = []) {
  const c = await getConnection();
  return new Promise((resolve, reject) =>
    c.execute({
      sqlText,
      binds,
      complete: (err, _stmt, rows) => (err ? reject(err) : resolve(rows ?? [])),
    })
  );
}

/** Creates or replaces one day's log for one product, like CheckInStore.record in the app. */
export async function upsertDailyLog(userId, log) {
  await query(
    `MERGE INTO daily_logs t
     USING (SELECT ? AS user_id, TO_DATE(?) AS day_key, ? AS product_type, ? AS quantity, ? AS unit,
                   ? AS craving_level, ? AS mood, ? AS note, ? AS source) s
     ON t.user_id = s.user_id AND t.day_key = s.day_key AND t.product_type = s.product_type
     WHEN MATCHED THEN UPDATE SET
       quantity = s.quantity, unit = s.unit,
       craving_level = COALESCE(s.craving_level, t.craving_level),
       mood = COALESCE(s.mood, t.mood), note = COALESCE(s.note, t.note),
       source = s.source, updated_at = CURRENT_TIMESTAMP()
     WHEN NOT MATCHED THEN INSERT
       (user_id, day_key, product_type, quantity, unit, craving_level, mood, note, source)
       VALUES (s.user_id, s.day_key, s.product_type, s.quantity, s.unit, s.craving_level, s.mood, s.note, s.source)`,
    [
      userId,
      log.dayKey,
      log.productType,
      log.quantity,
      log.unit,
      log.cravingLevel,
      log.mood,
      log.note,
      log.source,
    ]
  );
}

/** Daily totals for the last `days` days, newest first. */
export async function recentDays(userId, days = 60) {
  return query(
    `SELECT TO_VARCHAR(day_key, 'YYYY-MM-DD') AS "day", cigarettes, total_units, max_craving, mood
     FROM daily_totals
     WHERE user_id = ? AND day_key >= DATEADD(day, ?, CURRENT_DATE())
     ORDER BY day_key DESC`,
    [userId, -(days - 1)]
  );
}
