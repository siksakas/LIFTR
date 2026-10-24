import { test } from "node:test";
import assert from "node:assert/strict";
import { summarize } from "../src/stats.js";

const today = new Date(2026, 9, 24); // Oct 24, 2026 (months count from 0)
const day = (offset) => {
  const d = new Date(today);
  d.setDate(d.getDate() - offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const row = (offset, units, extra = {}) => ({ day: day(offset), cigarettes: units, total_units: units, max_craving: null, mood: null, ...extra });

test("no logs gives empty but valid stats", () => {
  const s = summarize([], today);
  assert.equal(s.days_logged_last_30, 0);
  assert.equal(s.avg_per_logged_day_last_30, null);
  assert.equal(s.change_vs_previous_30_percent, null);
});

test("averages and change compare the last 30 days with the 30 before", () => {
  const rows = [];
  for (let i = 0; i < 30; i++) rows.push(row(i, 5));
  for (let i = 30; i < 60; i++) rows.push(row(i, 10));
  const s = summarize(rows, today);
  assert.equal(s.avg_per_logged_day_last_7, 5);
  assert.equal(s.avg_per_logged_day_last_30, 5);
  assert.equal(s.avg_per_logged_day_previous_30, 10);
  assert.equal(s.change_vs_previous_30_percent, -50);
  assert.equal(s.days_logged_last_30, 30);
});

test("counts nicotine-free days, cravings and moods", () => {
  const rows = [
    row(0, 0, { max_craving: 4, mood: "proud" }),
    row(1, 0, { max_craving: 6, mood: "proud" }),
    row(2, 3, { mood: "stressed" }),
  ];
  const s = summarize(rows, today);
  assert.equal(s.nicotine_free_days_last_30, 2);
  assert.equal(s.avg_craving_last_7, 5);
  assert.deepEqual(s.common_moods_last_30, ["proud", "stressed"]);
  assert.equal(s.heaviest_weekday_last_30, new Date(`${day(2)}T12:00:00`).toLocaleDateString("en-US", { weekday: "long" }));
});
