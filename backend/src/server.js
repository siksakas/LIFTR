import express from "express";
import { upsertDailyLog, recentDays } from "./snowflake.js";
import { summarize } from "./stats.js";
import { coachReply } from "./coach.js";

const app = express();
app.use(express.json({ limit: "100kb" }));

const PRODUCTS = ["cigarette", "vape", "pouch", "cigar", "gum", "other"];
const UNITS = { cigarette: "cigarette", vape: "session", pouch: "pouch", cigar: "cigar", gum: "piece", other: "use" };

// Optional shared token. It only keeps out casual callers, since anything in the app can be extracted.
app.use((req, res, next) => {
  if (req.path === "/health" || !process.env.APP_TOKEN) return next();
  if (req.get("X-App-Token") === process.env.APP_TOKEN) return next();
  res.status(401).json({ error: "Missing or wrong X-App-Token header." });
});

/** Every data route needs to know whose data it is. The app sends its install ID. */
function userId(req, res) {
  const id = req.get("X-User-Id");
  if (!id || !/^[A-Za-z0-9-]{8,64}$/.test(id)) {
    res.status(400).json({ error: "Send the user's ID in the X-User-Id header (8 to 64 letters, digits or dashes)." });
    return null;
  }
  return id;
}

app.get("/health", (_req, res) => res.json({ ok: true }));

/**
 * Save one day's check-in. Same fields as DailyLog in the app.
 * Body: { dayKey: "2026-10-24", products: { cigarette: 3, vape: 1 }, cravingLevel?, mood?, note?, source? }
 * The older single-product form { dayKey, quantity, productType? } still works.
 * Sending the same day and product again overwrites it.
 */
app.post("/logs", async (req, res, next) => {
  const uid = userId(req, res);
  if (!uid) return;
  const b = req.body ?? {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(b.dayKey ?? "")) return res.status(400).json({ error: "dayKey must look like 2026-10-24." });

  const counts =
    b.products && typeof b.products === "object"
      ? b.products
      : { [b.productType ?? "cigarette"]: b.quantity ?? b.cigarettesSmoked };
  const products = [];
  for (const [productType, raw] of Object.entries(counts)) {
    const quantity = Number(raw);
    if (!PRODUCTS.includes(productType)) return res.status(400).json({ error: `Product types must be one of ${PRODUCTS.join(", ")}.` });
    if (!Number.isFinite(quantity) || quantity < 0) return res.status(400).json({ error: `${productType} must be 0 or more.` });
    products.push({ productType, quantity, unit: b.products ? UNITS[productType] : b.unit ?? UNITS[productType] });
  }
  if (!products.length) return res.status(400).json({ error: "Send at least one product count." });

  try {
    await upsertDailyLog(
      uid,
      {
        dayKey: b.dayKey,
        cravingLevel: Number.isFinite(b.cravingLevel) ? Math.min(Math.max(Math.round(b.cravingLevel), 0), 10) : null,
        mood: b.mood || null,
        note: b.note || null,
        source: b.source === "voice" ? "voice" : "manual",
      },
      products
    );
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** Daily totals for the last 60 days plus the summary the coach uses. */
app.get("/stats", async (req, res, next) => {
  const uid = userId(req, res);
  if (!uid) return;
  try {
    const days = await recentDays(uid, 60);
    res.json({ summary: summarize(days), days });
  } catch (err) {
    next(err);
  }
});

/**
 * Text chat with the coach.
 * Body: { messages: [{ role: "user", content: "I'm craving right now" }], appProgress?: { liftr_score, sober_streak_days, ... } }
 * appProgress lets the app pass the score and streak it already computes on the phone.
 */
app.post("/coach", async (req, res, next) => {
  const uid = userId(req, res);
  if (!uid) return;
  const messages = (req.body?.messages ?? []).filter(
    (m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string"
  );
  if (!messages.length) return res.status(400).json({ error: "Send at least one message." });
  try {
    const stats = summarize(await recentDays(uid, 60));
    const reply = await coachReply({ messages, stats, appProgress: req.body.appProgress });
    res.json({ reply });
  } catch (err) {
    next(err);
  }
});

/**
 * Conversation token for a private ElevenLabs agent.
 * Put this route's full URL in ConversationTokenURL in LIFTR/ElevenLabs.plist.
 */
app.get("/elevenlabs/token", async (_req, res, next) => {
  try {
    const r = await fetch(
      `https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=${encodeURIComponent(process.env.ELEVENLABS_AGENT_ID ?? "")}`,
      { headers: { "xi-api-key": process.env.ELEVENLABS_API_KEY ?? "" } }
    );
    if (!r.ok) throw new Error(`ElevenLabs returned ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const { token } = await r.json();
    res.json({ token });
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "Something went wrong on the server. Check the backend logs." });
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => console.log(`Liftr backend listening on http://localhost:${port}`));
