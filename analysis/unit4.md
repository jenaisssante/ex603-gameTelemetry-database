# Unit 4 — Aggregation: write-ups and reflection

Queries: [`queries/unit4/q4_1.sql`](../queries/unit4/q4_1.sql) (Task 4.1) and
[`queries/unit4/q4_2.sql`](../queries/unit4/q4_2.sql) (Task 4.2). The finding
for leadership is in [unit4-finding.md](unit4-finding.md).

**Definitions used throughout.** The producer is a match. The event is a
session: one row in `match_participants`. A *failure* is a session that ended
in a network timeout. The timeout rate is timeouts divided by *eligible*
sessions, meaning every session that was not a voluntary quit. That is the
population the Unit 3 dashboard intended to use. Eligibility is tested with
`IS DISTINCT FROM 'Player quit'` rather than `<> 'Player quit'`, so the 166
sessions with no disconnect reason are not silently dropped again. A
*platform-side drop* is any abandonment the player did not choose: a network
timeout, a server restart or a client crash. Region means the match's
`server_region`, which is where it is hosted.

---

## Task 4.1 — Measure the platform

### What the queries returned

| Query | Result |
|---|---|
| 4.1a-1 Platform totals | 200 sessions, total score 3,628.19, average 18.14, minimum 0.00, maximum 70.86, 30 distinct players |
| 4.1a-2 The zero minimum | All 34 abandoned sessions score exactly 0. No finished or contested session does. Sessions that produced a result average 21.86. |
| 4.1b Per match | From 21 sessions (match 6) down to 0 (matches 14 and 15). Match 11 has the lowest average score, 11.94. |
| 4.1c HAVING ≥ 15 sessions | 8 of 15 matches, holding 145 of the 200 sessions. Match 2: 3 timeouts in 16 sessions (18.8%). |
| 4.1d Region × match type | 7 combinations. APAC ranked holds 5 of the 12 timeouts. NA ranked has no timeouts in 19 sessions, all from one match. |

### Why the threshold is 15 sessions

The platform timeout rate is about 6%. At 15 sessions, one timeout reads as
6.7%. That is roughly the platform norm, so a single isolated timeout cannot
make a match look abnormal. Below 15 sessions, one timeout already reads as
7.1% or higher. At 5 sessions (match 4), one timeout reads as 20%. A rate that
one event can move that far measures luck, not the match. Fifteen is also just
under the median volume of the matches that recorded any sessions (16), so the
bar keeps the typical match rather than only the busiest. The matches below the
bar are listed in 4.1c-2, not discarded silently, so their rates can be watched
as volume builds.

### Who acts on the per-match breakdown

The **live-ops server operations lead**, who owns match hosting and the network
path between players and game servers. A per-match timeout count tells them
which hosts to pull logs for. Leadership can decide whether rewards are fair,
but only the server operations lead can find out *why* match 2 drops
connections and fix it.

### What the aggregates hide

**The average hides its distribution.** The platform average of 18.14 is not a
typical score. The distribution has two parts: 34 sessions at exactly 0 (every
abandonment) and 166 real results ranging from 4.65 to 70.86. Averaging the
zeros in turns a reliability problem into what looks like a skill problem.
Match 11's average of 11.94 looks like weak play. In fact, 5 of its 16 sessions
were abandoned and scored 0, and its sessions that produced a result average
17.37. Any per-match average in this dataset is partly a failure count in
disguise.

**The count hides who is counted.** The count measures sessions, not players or
games:

- Match 6 is listed with a `player_count` of 4 but recorded 21 sessions from 14
  different players. `player_count` is a configured lobby size, not attendance.
- 39 (player, match) pairs appear more than once, so one player can contribute
  several sessions to a match. The Unit 2 schema keyed on (match, player) would
  have rejected these rows.
- The sessions inside a single match span most of 2023. Match 2's three
  timeouts happened in January, March and December. A "match" here behaves
  like a recurring lobby or server, not a single game.
- An inner join counts only matches that have sessions. Matches 14 and 15 are
  real producers with no recorded activity, and they vanish from any query that
  starts from the event table.

### What I would need to see next

1. **Timeouts over time.** Plot `joined_at` per match to show whether match 2's
   timeouts are scattered or clustered after a specific date, such as a server
   change.
2. **Timeouts by player.** Twelve timeouts fall on 10 players. Players 1 and 21
   each timed out twice in different matches. That points at their connection
   rather than at a server.
3. **Server region against client region.** The two regions disagree on 160 of
   200 sessions. A timeout rate split by the distance between player and server
   would separate a bad host from long-haul routing.
4. **Session length before failure.** `duration_min` on the timed-out rows
   shows how much play each timeout destroyed, which is the reward impact
   leadership actually pays for.
5. **Game mode.** This needs `match_modes`. A match can carry several modes, so
   joining it multiplies sessions. The rate has to be computed per match before
   it is joined to mode, or every multi-mode match is counted more than once.

---

## Task 4.2 — The breakdown leadership asked for

### Part A — Two numbers in one pass

The conditional aggregation answers two questions side by side for every match:

1. **How many sessions did this match record?** (`COUNT(*)`)
2. **How many of them ended in a network timeout?**
   (`SUM(CASE WHEN disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END)`)

Because both numbers come from the same group of rows, the rate is their
quotient, with no join and no chance of the two counts being computed over
different populations. The same pass also produces the eligible-session count
and the platform-side drop count. There is no `WHERE` clause, because a
`WHERE` would remove rows from *every* column. Each condition lives inside its
own aggregate, so each column filters only itself.

The outliers this surfaced:

- **Match 2:** 3 timeouts in 16 sessions (18.8%), a quarter of every timeout on
  the platform.
- **Match 11:** only 1 timeout, but 4 platform-side drops in 15 eligible
  sessions, the joint highest.
- **Match 3** (2 in 13) and **match 4** (1 in 5) have high rates on volume too
  low to rely on.

### Part B — Subtotals and a grand total

`GROUP BY ROLLUP (server_region)` produces one row per region and one extra row
in which the region has been rolled up to "all regions". The query labels the
rows with `GROUPING(server_region)` instead of leaving a bare NULL:

| Rows | `row_type` value | Meaning |
|---|---|---|
| APAC, EU, NA, OCE, SA | `Regional subtotal` | Totals for every match hosted in that region |
| Last row, `ALL REGIONS` | `Platform grand total` | Totals for all 15 matches |

**Who needs subtotals rather than detail rows:** the **regional director**. They
manage regions, not individual matches. Fifteen detail rows would make them do
the addition themselves. Five subtotals tell them directly which region's
infrastructure is producing failures: APAC carries 5 of the 12 timeouts and 11
of the 27 platform-side drops.

**What decision the grand total supports:** whether the platform as a whole is
healthy enough to keep paying ranked rewards on schedule. The grand total gives
6.2% timeouts and 14.0% platform-side drops over 193 eligible sessions. It is
the one number that can be compared with the dashboard's original "about half"
and with any future target. A regional row cannot answer that, because no
single region represents the platform. The grand total is also the
reconciliation check Unit 3 asked for: the five regional session counts sum to
the 200 sessions in the table, so nothing was dropped.

### Part C — A two-step pipeline

**The question the pipeline answers:** *for a match busy enough to judge, what
timeout rate and what platform-side drop rate count as normal, and which busy
matches are far from it?*

- **Step 1 (`per_match`):** summarise every match from the event table into
  sessions, eligible sessions, timeouts and platform-side drops.
- **Step 2:** keep the matches with at least 15 sessions and aggregate them
  again into a baseline. The pooled timeout rate is 5.0% (7 of 140 eligible
  sessions) and the pooled drop rate is 12.1% (17 of 140). The mean of the
  individual match rates, 5.3%, sits close to the pooled 5.0%, so no single
  match is distorting the baseline.
- **4.2c-2** carries the pipeline one step further. It compares each
  high-volume match with the baseline and flags any match at twice the baseline
  or more on either measure. Two matches are flagged, both hosted in APAC:
  match 2 for timeouts (3.8×) and match 11 for platform-side drops (2.2×).

The baseline uses only high-volume matches on purpose. Including match 4 (1
timeout in 5 sessions) would let one event move the yardstick that every other
match is judged against.

---

## Reflection — conditional aggregation vs separate filtered queries

Conditional aggregation reads the event table once. Each row is examined, and
each `CASE` decides which running totals it adds to: total sessions, eligible
sessions, timeouts and drops are all accumulated in the same scan and grouped
in the same step. Two separate filtered queries, one `COUNT(*)` grouped by
match and one `COUNT(*) WHERE disconnect_reason = 'Network timeout'` grouped by
match, each scan the table and each build their own grouping. They then have to
be joined on `match_id` to put the numbers side by side.

At 200 rows the difference is invisible. At a million rows it matters for three
reasons. First, cost: each extra metric is another full scan, another hash
aggregate and another join. Four metrics done separately means four reads of a
million rows instead of one. Second, consistency: on a live telemetry table,
rows arrive between two separate queries, so the numerator and denominator can
describe different moments and the rate can drift or even exceed 100%. One
pass computes both from the same snapshot. Third, correctness of the join: the
filtered timeout query returns no row at all for a match with zero timeouts.
Joining it to the totals with an inner join silently drops the healthiest
matches, which is the same class of silent loss that broke the Unit 3
dashboard. A `CASE` inside the aggregate returns 0 for those matches instead of
nothing.
