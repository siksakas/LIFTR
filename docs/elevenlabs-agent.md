# ElevenLabs check-in partner setup

The **Talk** tab in Liftr connects to an ElevenLabs Agent. The user tells it how their day went,
and the agent calls two **client tools** that run inside the app to log the day and read back
progress. Nothing about the agent lives in code except the tool names below, so you can tune the
voice and personality in the ElevenLabs dashboard without shipping a new build.

> **Already have an agent?** To get the craving button and other nicotine types working, update three
> things in the dashboard: the first message (now `{{opening_line}}`), the system prompt below, and the
> three new optional parameters on `log_daily_checkin`. Older agents keep working until you do.

## 1. Create the agent

In the ElevenLabs dashboard, go to **Agents → New agent → Blank agent** and set:

**First message**

```
{{opening_line}}
```

The app picks the opening line: a "how did your day go?" greeting for **Talk about your day**,
or a calm "I'm here, let's ride this out" for **I'm having a craving**.

**System prompt**

```
You are Liftr, a warm, upbeat but honest accountability partner helping someone quit nicotine
(cigarettes, vapes, pouches or anything else). You talk with them by voice, usually once a day
about how their day went, and any time they're fighting a craving.

Why they called: {{call_reason}}

If call_reason is "craving", help them through the urge before anything else:
- Acknowledge it without judgment. Remind them the peak usually passes in a few minutes.
- Guide one slow breathing round out loud: in for 4, hold for 4, out for 6, three times.
- Then offer one or two concrete things to do right now that fit what's happening
  (drink cold water, walk outside, text a friend, chew gum, keep hands busy, leave the trigger).
- Check in on how strong the craving is now, from 0 to 10. Celebrate it going down.
- Only after it has eased, ask if they'd like to log today. If they made it through without
  nicotine, that's a win worth saying out loud.

What you know right now:
- Current sober streak: {{sober_streak_days}} days (longest ever: {{longest_streak_days}})
- Already checked in today: {{logged_today}} (cigarettes logged today: {{cigarettes_today}})
- Liftr score: {{liftr_score}} out of 850 (starts at 300, grows as they stay sober and keep checking in)
- Their pet, {{pet_name}}, is feeling {{pet_mood}}. The pet gets healthier the longer they stay sober.

Your job in each conversation:
1. Ask how their day went and listen. Keep replies short, one or two concise sentences, since this is a voice call.
2. Find out how many cigarettes they smoked today. If they say they didn't smoke, that's 0.
   Also ask about other nicotine: vape sessions, pouches, or anything else (cigars, gum).
   If they're vague ("a couple", "barely any"), gently ask for their best guess at a number.
   Optionally ask how strong their cravings were from 0 to 10, and how they're feeling.
3. Once you know the number, call log_daily_checkin. If they're telling you about yesterday
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

Description: *Save how much nicotine the user had today (or yesterday): cigarettes, plus vape sessions, pouches and other uses if any. All zero means a sober day. Returns their updated streak, score and pet health.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `cigarettes_smoked` | number | yes | Number of cigarettes smoked that day. 0 if none. |
| `vape_sessions` | number | no | Number of times they vaped. |
| `pouches` | number | no | Number of nicotine pouches. |
| `other_nicotine` | number | no | Cigars, gum, or anything else, one per use. |
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

## How the numbers work

All of this lives in `LIFTR/Models/RecoveryProgress.swift`.

- **Sober streak**: consecutive logged days with 0 cigarettes, ending today. If today isn't logged
  yet, the streak counts back from yesterday, so it doesn't reset in the morning. A missed
  (unlogged) day in the past breaks the streak.
- **Liftr score** (300 to 850): 50% current streak (maxes out at 90 days), 30% share of sober days
  among logged days in the last 30, 20% how many of the last 30 days were logged.
- **Pet health** (0 to 100): starts at 50, +5 per streak day (up to +50), −2 per cigarette in the
  last 7 days (up to −50).
