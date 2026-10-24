# Liftr backend

A small Node server that holds every API key, so the iOS app never has to. It does three things:

- **Saves check-ins to Snowflake**, one row per user, day and product, mirroring `DailyLog` in the app.
- **Runs the AI coach** on an open-weights model through DigitalOcean's serverless inference. Snowflake
  and `src/stats.js` compute the numbers; the model only puts them into words.
- **Hands out ElevenLabs conversation tokens**, so the voice agent can be private
  (see "Public vs private agent" in `docs/elevenlabs-agent.md`).

The app keeps working without it: logs still save on the phone. The backend adds cloud storage, trends
across devices, and the text coach.

## Set up

1. **Snowflake.** Open a SQL worksheet in Snowsight, paste all of `snowflake/setup.sql`, select
   everything (Ctrl/Cmd + A) and run it. Copy the `token_secret` from the last result; it's shown once.
2. **DigitalOcean.** In the control panel, open serverless inference under the AI platform, then
   Model Access Keys, and create one.
3. **ElevenLabs.** Create an API key in your account settings. Set up the agent with
   `docs/elevenlabs-agent.md`.
4. **Keys.** `cp .env.example .env` in this folder and fill it in. `.env` is gitignored; never commit it,
   paste it in chat, or put any of these keys in the iOS app.

## Run it

Needs Node 22 or newer (`node -v`).

```sh
cd backend
npm install
npm run dev     # restarts when you edit a file
npm test        # checks the stats math
```

Then try it from another terminal:

```sh
curl localhost:8080/health

curl -X POST localhost:8080/logs -H "Content-Type: application/json" -H "X-User-Id: demo-user-0001" \
  -d '{"dayKey":"2026-10-24","products":{"cigarette":3,"vape":1},"cravingLevel":6,"mood":"stressed"}'

curl localhost:8080/stats -H "X-User-Id: demo-user-0001"

curl -X POST localhost:8080/coach -H "Content-Type: application/json" -H "X-User-Id: demo-user-0001" \
  -d '{"messages":[{"role":"user","content":"I really want a cigarette right now"}]}'

curl localhost:8080/elevenlabs/token
```

## Connect the iPhone app

1. Start the backend on your Mac with `npm run dev`.
2. Run the app in the simulator, open the **Coach** tab, and save `http://localhost:8080`.
   (Or copy `Config/Backend.example.plist` to `LIFTR/Backend.plist`, which is gitignored.)
3. From then on, every check-in, manual or by voice, also syncs to Snowflake. A failed sync retries the
   next time you log or reopen the app. The Coach tab shows a warning while syncing fails.

On a real iPhone, `localhost` means the phone itself. Use your Mac's Wi-Fi address instead (System
Settings → Wi-Fi → Details, for example `http://192.168.1.20:8080`), or the deployed DigitalOcean URL.

## Routes

| Route | What it does |
|---|---|
| `GET /health` | Returns `{"ok":true}`. No headers needed. |
| `POST /logs` | Saves a day, one Snowflake row per product. Body: `dayKey` (`yyyy-MM-dd`), `products` (counts by type: cigarette, vape, pouch, cigar, gum, other), and optionally `cravingLevel` (0 to 10), `mood`, `note`, `source` (`voice` or `manual`). The older `quantity` + `productType` form still works. Same day and product again overwrites it. |
| `GET /stats` | Last 60 days of daily totals plus a summary: averages for the last 7 and 30 days, change against the 30 days before, nicotine-free days, heaviest weekday, cravings and moods. |
| `POST /coach` | Body: `messages` (the chat so far) and optionally `appProgress` (the score and streak the app already computed). Returns `{"reply": "..."}`. |
| `GET /elevenlabs/token` | Returns `{"token": "..."}` for the app's `ConversationTokenURL`. |

Data routes need an `X-User-Id` header: a random ID the app creates once and keeps (for example
`UUID().uuidString` saved in UserDefaults). If `APP_TOKEN` is set, every route but `/health` also needs
an `X-App-Token` header with that value.

## Deploy on DigitalOcean App Platform

`.do/app.yaml` at the repo root describes the app, so most settings are filled in for you.

1. In DigitalOcean, go to **Apps → Create App**, connect GitHub, and choose **siksakas/LIFTR**.
   If it offers to use the app spec it found, accept it. Otherwise pick **Import from App Spec** and
   upload `.do/app.yaml`. (With the CLI: `doctl apps create --spec .do/app.yaml`.)
2. Open the app's **Settings → Environment Variables** and paste the values for the secrets:
   `SNOWFLAKE_PAT`, `DO_MODEL_ACCESS_KEY`, `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`. Leave
   `APP_TOKEN` empty unless you also put it in `LIFTR/Backend.plist`.
3. Deploy. When it's live, `https://<your-app>.ondigitalocean.app/health` returns `{"ok":true}`.
   Every push to `main` redeploys it.
4. In the app's **Coach** tab (or `LIFTR/Backend.plist`), use that https address instead of localhost.
   It then works on a real iPhone anywhere, not only next to your Mac.
5. Optional: put `https://<your-app>.ondigitalocean.app/elevenlabs/token` into `ConversationTokenURL`
   in `LIFTR/ElevenLabs.plist` and turn on authentication on the ElevenLabs agent.

The smallest instance costs a few dollars a month. Destroy the app after the hackathon if you don't need it.
