# ElevenLabs check-in partner setup

The **Talk** tab in Liftr connects to an ElevenLabs Agent. The user tells it how their day went,
and the agent calls two **client tools** that run inside the app to log the day and read back
progress. Nothing about the agent lives in code except the tool names below, so you can tune the
voice and personality in the ElevenLabs dashboard without shipping a new build.

## 1. Create the agent

In the ElevenLabs dashboard, go to **Agents → New agent → Blank agent** and set:

**First message**

```
Hey! Good to hear from you. {{pet_name}} is feeling {{pet_mood}} today. How did your day go?
```

**System prompt**

```
You are Liftr, a warm, upbeat but honest accountability partner helping someone quit smoking.
You talk with them once a day, by voice, about how their day went.

What you know right now:
- Current sober streak: {{sober_streak_days}} days (longest ever: {{longest_streak_days}})
- Already checked in today: {{logged_today}} (cigarettes logged today: {{cigarettes_today}})
- Liftr score: {{liftr_score}} out of 850 (starts at 300, grows as they stay sober and keep checking in)
- Their pet, {{pet_name}}, is feeling {{pet_mood}}. The pet gets healthier the longer they stay sober.
- Cigarettes they tapped on their Apple Watch since you last talked: {{watch_cigarettes_since_last_talk}}
  (when: {{watch_cigarette_times}}). These are already saved and already included in cigarettes_today.

Your job in each conversation:
1. Ask how their day went and listen. Keep replies short, two or three sentences, since this is a voice call.
   If they logged cigarettes on their watch since you last talked, bring them up early, warmly and
   without judgment: thank them for logging honestly, mention roughly when ("I saw one around 3pm"),
   and ask what was going on at the time, so you can spot triggers together.
2. Find out how many cigarettes they smoked today. If they say they didn't smoke, that's 0.
   If they're vague ("a couple", "barely any"), gently ask for their best guess at a number.
   Watch logs count toward today's total, so confirm the full number ("so that's the two from your
   watch, anything else since?") rather than asking from scratch.
   Optionally ask how strong their cravings were from 0 to 10, and how they're feeling.
3. Once you know the number, call log_daily_checkin with the full total for the day, including
   cigarettes logged on the watch. If they're telling you about yesterday
   (for example, they forgot to check in), pass day = "yesterday".
4. Use the result to respond: celebrate the streak and score going up on a sober day; on a day
   they smoked, be kind and non-judgmental, note that the streak restarts and the score will
   recover, and help them plan for tomorrow (triggers, what they'll do instead).
5. If they ask about their progress, call get_progress.

Rules:
- Never shame or lecture. Relapses are part of quitting.
- Don't invent numbers. Only use what the tools return.
- If they correct themselves, call log_daily_checkin again with the right number; it overwrites that day.
- You are not a doctor. If they mention severe withdrawal, chest pain, or thoughts of self-harm,
  encourage them to contact a medical professional or emergency services.
```

All nine `{{variables}}` above are sent by the app when the call starts. If you add a new
variable to the prompt, add it to `dynamicVariables()` in `LIFTR/Voice/CheckInPartner.swift` too,
or the conversation will fail to start.

Pick any voice you like under **Voice**.

## 2. Add the client tools

Under the agent's **Tools → Add tool → Client**, add these two tools. Turn on
**Wait for response** for both so the agent hears the result.

### `log_daily_checkin`

Description: *Save how many cigarettes the user smoked today (or yesterday). 0 means a sober day. Returns their updated streak, score and pet health.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `cigarettes_smoked` | number | yes | Number of cigarettes smoked that day. 0 if sober. |
| `day` | string | no | `today` (default) or `yesterday`. |
| `craving_level` | number | no | Craving strength from 0 (none) to 10 (overwhelming). |
| `mood` | string | no | One or two words for how they felt, e.g. "stressed", "proud". |
| `notes` | string | no | Short summary of what happened, triggers, or wins. |

Returns JSON like:

```json
{"cigarettes_last7_days":0,"liftr_score":412,"logged_cigarettes":0,"logged_day":"today",
 "logged_today":true,"longest_streak_days":5,"pet_health":75,"pet_mood":"happy","pet_name":"Sprout",
 "score_change":14,"sober_streak_days":5,"status":"logged","total_sober_days":9, ...}
```

### `get_progress`

Description: *Get the user's current sober streak, Liftr score, and pet health.* No parameters.

## 3. Point the app at the agent

1. Copy `Config/ElevenLabs.example.plist` to `LIFTR/ElevenLabs.plist` (this path is gitignored).
2. Set `AgentID` to the agent's ID (shown on the agent page, starts with `agent_`).
3. Build and run. Xcode will fetch the `ElevenLabs` Swift package the first time.

Or skip the plist: run the app, open the **Talk** tab, and paste the agent ID into the setup card.
It's saved on the device. A plist, if present, takes priority.

### Public vs private agent

- **Public agent** (simplest, fine for development): leave authentication off on the agent and
  leave `ConversationTokenURL` empty. Anyone with the agent ID can talk to it and spend your credits.
- **Private agent** (for release): turn on authentication and run a tiny backend that calls
  `GET https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=<id>` with your
  `xi-api-key` and returns `{"token": "..."}`. Put that endpoint's URL in `ConversationTokenURL`.
  Never put the ElevenLabs API key in the app.

## Apple Watch quick log

The **LIFTR Watch App** target has one big "I smoked one" button (with an 8-second undo). Each tap
is sent to the phone with WatchConnectivity and saved as a `CigaretteEvent` with its exact time;
it also adds one to that day's `DailyLog`, so the streak, score and pet update right away. Taps made
while the phone is out of reach are queued and delivered later.

When a voice check-in starts, the app sends the watch cigarettes the partner hasn't been told about
yet (from the last 7 days) as `watch_cigarettes_since_last_talk` (a count) and `watch_cigarette_times`
(e.g. "today at 9:14 AM, today at 1:40 PM", or "none"). Each one is marked as talked about once the
call connects, so a tap that reaches the phone late still comes up in the next call.

If a tap reaches the phone late, after a voice or manual check-in already saved that day's full
total, it's kept for the record but not added again, since the total already included it.

To run it, pick the **LIFTR Watch App** scheme and a paired watch simulator, or just install the
iPhone app on a phone with a paired watch; the watch app is embedded in the iPhone app.

## How the numbers work

All of this lives in `LIFTR/Models/RecoveryProgress.swift`.

- **Sober streak**: consecutive logged days with 0 cigarettes, ending today. If today isn't logged
  yet, the streak counts back from yesterday, so it doesn't reset in the morning. A missed
  (unlogged) day in the past breaks the streak.
- **Liftr score** (300 to 850): 50% current streak (maxes out at 90 days), 30% share of sober days
  among logged days in the last 30, 20% how many of the last 30 days were logged.
- **Pet health** (0 to 100): starts at 50, +5 per streak day (up to +50), −2 per cigarette in the
  last 7 days (up to −50).
