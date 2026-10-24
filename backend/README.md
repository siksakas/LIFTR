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
  -d '{"dayKey":"2026-10-24","quantity":3,"cravingLevel":6,"mood":"stressed"}'

curl localhost:8080/stats -H "X-User-Id: demo-user-0001"

curl -X POST localhost:8080/coach -H "Content-Type: application/json" -H "X-User-Id: demo-user-0001" \
  -d '{"messages":[{"role":"user","content":"I really want a cigarette right now"}]}'

curl localhost:8080/elevenlabs/token
```

## Routes

| Route | What it does |
|---|---|
| `GET /health` | Returns `{"ok":true}`. No headers needed. |
| `POST /logs` | Saves a day. Body: `dayKey` (`yyyy-MM-dd`), `quantity`, and optionally `productType` (cigarette, vape, pouch, cigar, gum, other; default cigarette), `unit`, `cravingLevel` (0 to 10), `mood`, `note`, `source` (`voice` or `manual`). Same day and product again overwrites it. |
| `GET /stats` | Last 60 days of daily totals plus a summary: averages for the last 7 and 30 days, change against the 30 days before, nicotine-free days, heaviest weekday, cravings and moods. |
| `POST /coach` | Body: `messages` (the chat so far) and optionally `appProgress` (the score and streak the app already computed). Returns `{"reply": "..."}`. |
| `GET /elevenlabs/token` | Returns `{"token": "..."}` for the app's `ConversationTokenURL`. |

Data routes need an `X-User-Id` header: a random ID the app creates once and keeps (for example
`UUID().uuidString` saved in UserDefaults). If `APP_TOKEN` is set, every route but `/health` also needs
an `X-App-Token` header with that value.

## Deploy on DigitalOcean App Platform

1. Create App → GitHub → this repo, and set the **source directory** to `backend`.
2. It detects Node and runs `npm start`. Set the HTTP port to 8080.
3. Add every variable from `.env.example` under the app's environment variables and tick **Encrypt**
   for the secrets.
4. Once it's live, put `https://<your-app>.ondigitalocean.app/elevenlabs/token` into `ConversationTokenURL`
   in `LIFTR/ElevenLabs.plist`, and turn on authentication on the ElevenLabs agent. The app then also
   uses this backend for Coach's typed replies and to save each day's counts. To use the backend
   without a private agent, set `BackendURL` (and `AppToken`, if you set `APP_TOKEN`) in the plist instead.
