const DO_URL = "https://inference.do-ai.run/v1/chat/completions";

const SYSTEM_PROMPT = `You are Liftr, a warm, practical coach helping someone cut down and quit nicotine.
Use ONLY the numbers in USER_STATS and APP_PROGRESS. Never invent figures. If a number is null, it isn't known yet.
If they're having a craving: give 2 or 3 concrete things to do in the next five minutes, and remind them urges usually pass within a few minutes.
If they ask about progress or habits: name one specific win, then one pattern to work on.
Never shame or lecture. Relapses are part of quitting.
Keep replies under 120 words.
You are not a doctor. For medication or nicotine replacement questions, suggest a clinician or a quitline (1-800-QUIT-NOW in the US).
If they mention chest pain, severe withdrawal or thoughts of self-harm, tell them to contact a medical professional or emergency services.`;

/**
 * Asks the open-weights model on DigitalOcean for the coach's reply.
 * `messages` is the chat so far: [{ role: "user" | "assistant", content }].
 * The model remembers nothing between calls, so the app sends the whole chat each time.
 */
export async function coachReply({ messages, stats, appProgress }) {
  const system = `${SYSTEM_PROMPT}\nUSER_STATS: ${JSON.stringify(stats)}\nAPP_PROGRESS: ${JSON.stringify(appProgress ?? {})}`;

  const res = await fetch(DO_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.DO_MODEL_ACCESS_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.DO_MODEL_ID ?? "llama3.3-70b-instruct",
      messages: [{ role: "system", content: system }, ...messages.slice(-20)],
      temperature: 0.6,
      max_tokens: 400,
    }),
  });
  if (!res.ok) {
    throw new Error(`DigitalOcean returned ${res.status}: ${(await res.text()).slice(0, 300)}`);
  }
  const data = await res.json();
  return data.choices?.[0]?.message?.content?.trim() ?? "";
}
