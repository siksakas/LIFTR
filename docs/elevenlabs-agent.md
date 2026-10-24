# ElevenLabs check-in partner setup

The **Voice** mode of the **Coach** tab in Liftr connects to an ElevenLabs Agent (craving help's
mic button opens it too). The user tells it how their day went,
and the agent calls two **client tools** that run inside the app to log the day and read back
progress. Nothing about the agent lives in code except the tool names below, so you can tune the
voice and personality in the ElevenLabs dashboard without shipping a new build.

## 1. Create the agent

In the ElevenLabs dashboard, go to **Agents → New agent → Blank agent** and set:

**First message**

```
{{opening_message}}
```

The app writes this line when the call starts, from what's already logged today: nothing yet,
a sober day so far, or the cigarettes, vapes and pouches logged and how that compares with the
user's usual by this time of day.

**System prompt**

```
You are Liftr, a warm, upbeat but honest accountability partner helping someone quit smoking.
You talk with them once a day, by voice, about how their day went.

What you know right now:
- Current sober streak: {{sober_streak_days}} days (longest ever: {{longest_streak_days}})
- Already checked in today: {{logged_today}} (cigarettes logged today: {{cigarettes_today}})
- Liftr score: {{liftr_score}} out of 850 (starts at 300, grows as they cut down; a slip only nudges it down)
- Their tortoise companion, {{pet_name}}, is at the "{{tuk_stage}}" stage and feeling {{pet_mood}}.
  Tuk mirrors their habit and gets healthier as they cut down.

Your job in each conversation:
1. Ask how their day went and listen. Keep replies short, one or two concise sentences, since this is a voice call.
2. Find out how many cigarettes they smoked today. If they say they didn't smoke, that's 0.
   If they're vague ("a couple", "barely any"), gently ask for their best guess at a number.
   Optionally ask how strong their cravings were from 0 to 10, and how they're feeling.
3. Once you know the number, call log_daily_checkin. If they're telling you about yesterday
   (for example, they forgot to check in), pass day = "yesterday".
4. Use the result to respond: celebrate fewer cigarettes and the score going up; on a harder day,
   be kind and non-judgmental, note that one day only nudges the score and Tuk moves back one
   stage at most, and help them plan for tomorrow (triggers, what they'll do instead).
5. If they ask about their progress, call get_progress.

Rules:
- Never shame or lecture. Relapses are part of quitting.
- Don't invent numbers. Only use what the tools return.
- If they correct themselves, call log_daily_checkin again with the right number; it overwrites that day.
- You are not a doctor. If they mention severe withdrawal, chest pain, or thoughts of self-harm,
  encourage them to contact a medical professional or emergency services.
```

All nine `{{variables}}` above are sent by the app when the call starts. (`pet_name` and
`pet_mood` keep their old names so agents set up before Tuk keep working.) If you add a new
variable to the prompt, add it to `dynamicVariables()` in `LIFTR/Voice/CheckInPartner.swift` too,
or the conversation will fail to start.

Pick any voice you like under **Voice**.

## 2. Add the client tools

Under the agent's **Tools → Add tool → Client**, add these two tools. Turn on
**Wait for response** for both so the agent hears the result.

### `log_daily_checkin`

Description: *Save how many cigarettes the user smoked today (or yesterday). 0 means a sober day. Returns their updated streak, score and Tuk's stage.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `cigarettes_smoked` | number | yes | Number of cigarettes smoked that day. 0 if sober. |
| `day` | string | no | `today` (default) or `yesterday`. |
| `craving_level` | number | no | Craving strength from 0 (none) to 10 (overwhelming). |
| `mood` | string | no | One or two words for how they felt, e.g. "stressed", "proud". |
| `notes` | string | no | Short summary of what happened, triggers, or wins. |

Returns JSON like:

```json
{"cigarettes_last7_days":0,"liftr_score":548,"logged_cigarettes":0,"logged_day":"today",
 "logged_today":true,"longest_streak_days":5,"pet_mood":"sleepy but hopeful","pet_name":"Tuk",
 "score_change":14,"score_change_this_week":18,"sober_streak_days":5,"status":"logged",
 "total_sober_days":9,"tuk_stage":"Cutting down","tuk_stage_number":2, ...}
```

### `get_progress`

Description: *Get the user's current sober streak, Liftr score, and Tuk's stage.* No parameters.

## 3. Point the app at the agent

1. Copy `Config/ElevenLabs.example.plist` to `LIFTR/ElevenLabs.plist` (this path is gitignored).
2. Set `AgentID` to the agent's ID (shown on the agent page, starts with `agent_`).
3. Build and run. Xcode will fetch the `ElevenLabs` Swift package the first time.

Or skip the plist: run the app, open **Coach**, switch to **Voice**, and paste the agent ID into the setup card.
It's saved on the device. A plist, if present, takes priority.

### Public vs private agent

- **Public agent** (simplest, fine for development): leave authentication off on the agent and
  leave `ConversationTokenURL` empty. Anyone with the agent ID can talk to it and spend your credits.
- **Private agent** (for release): turn on authentication and run a tiny backend that calls
  `GET https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=<id>` with your
  `xi-api-key` and returns `{"token": "..."}`. Put that endpoint's URL in `ConversationTokenURL`.
  Never put the ElevenLabs API key in the app.

## How the numbers work

All of this lives in `LIFTR/Models/RecoveryProgress.swift`. Cigarettes, vapes and nicotine pouches
all count.

- **Sober streak**: consecutive logged days with no nicotine, ending today. If today isn't logged
  yet, the streak counts back from yesterday, so it doesn't reset in the morning. A missed
  (unlogged) day in the past breaks the streak.
- **Baseline**: the user's usual amount per day, the average of their first 7 logged days.
- **Liftr score** (300 to 850): each logged day scores from 0 (the baseline or more) to 1 (none),
  so going from 6 a day to 3 scores 0.5. The score is 70% the average over the last 3 months and
  30% the average since day one. It needs 14 logged days for full credit, so one good first day
  doesn't jump to the top. Unlogged days don't count either way, and one slip is one day among many.
- **Tuk's stage** follows the score: Smoking 300–449, Cutting down 450–579, Recovering 580–669,
  Healthy 670–749, Thriving 750–850. A slip moves Tuk back one stage at most below the best stage
  reached, and never back to Smoking once Tuk has left it.
