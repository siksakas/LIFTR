/**
 * Turns daily totals into the small summary the coach reads. The database and this file do
 * the math; the language model only puts it into words, so it never has to invent a number.
 *
 * `rows` are { day: "yyyy-MM-dd", cigarettes, total_units, max_craving, mood }, any order.
 * Days with no row were not logged.
 */
export function summarize(rows, today = new Date()) {
  const byDay = new Map(rows.map((r) => [r.day, r]));
  const dayKey = (offset) => {
    const d = new Date(today);
    d.setDate(d.getDate() - offset);
    return [d.getFullYear(), d.getMonth() + 1, d.getDate()]
      .map((n, i) => String(n).padStart(i === 0 ? 4 : 2, "0"))
      .join("-");
  };

  const window = (from, to) => {
    const logged = [];
    for (let offset = from; offset < to; offset++) {
      const row = byDay.get(dayKey(offset));
      if (row) logged.push(row);
    }
    return logged;
  };
  const avg = (list) =>
    list.length ? round1(list.reduce((sum, r) => sum + Number(r.total_units), 0) / list.length) : null;

  const last7 = window(0, 7);
  const last30 = window(0, 30);
  const prev30 = window(30, 60);

  const moods = {};
  for (const r of last30) if (r.mood) moods[r.mood] = (moods[r.mood] ?? 0) + 1;

  const weekday = {};
  for (const r of last30) {
    const name = new Date(`${r.day}T12:00:00`).toLocaleDateString("en-US", { weekday: "long" });
    weekday[name] ??= { total: 0, days: 0 };
    weekday[name].total += Number(r.total_units);
    weekday[name].days += 1;
  }
  const worstDay = Object.entries(weekday)
    .map(([name, w]) => [name, w.total / w.days])
    .sort((a, b) => b[1] - a[1])[0];

  const cravings = last7.map((r) => r.max_craving).filter((c) => c != null);

  return {
    days_logged_last_30: last30.length,
    nicotine_free_days_last_30: last30.filter((r) => Number(r.total_units) === 0).length,
    avg_per_logged_day_last_7: avg(last7),
    avg_per_logged_day_last_30: avg(last30),
    avg_per_logged_day_previous_30: avg(prev30),
    change_vs_previous_30_percent:
      avg(prev30) && avg(last30) != null ? Math.round(((avg(last30) - avg(prev30)) / avg(prev30)) * 100) : null,
    heaviest_weekday_last_30: worstDay && worstDay[1] > 0 ? worstDay[0] : null,
    avg_craving_last_7: cravings.length ? round1(cravings.reduce((a, b) => a + b, 0) / cravings.length) : null,
    common_moods_last_30: Object.entries(moods)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([m]) => m),
  };
}

function round1(n) {
  return Math.round(n * 10) / 10;
}
