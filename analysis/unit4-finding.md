# Finding: the true network-timeout rate is 6.2%, and two APAC matches drive it

**To:** Leadership team
**From:** Trust and Data
**Re:** The actual failure rate, and which matches contribute most to it

**The true rate.** Across the platform, 12 of 193 sessions ended in a network
timeout, a rate of **6.2%**. The 193 sessions are every session except the 7
where the player chose to quit. Counting all 200 sessions, quits included, the
rate is 6.0%. In ranked matches alone it is 5.4%, the figure we reported last
time. The original dashboard's "about half" was wrong by a factor of eight.
Timeouts are only one way a player can be dropped by something outside their
control. Adding server restarts and client crashes gives 27 such drops, or
**14.0%** of eligible sessions. That wider figure is the better measure of how
often the platform lets a player down.

**How it varies across matches.** Most matches are close to normal. Of the 13
matches that recorded any play, 4 had no timeouts at all, 7 had exactly
one, and only 2 had more than one. We judged only the 8 matches with at least 15 sessions, because
below that a single timeout is enough to make a match look bad. For those
busier matches, a normal timeout rate is **5.0%** and a normal drop rate is
**12.1%**. Region matters more than any single match: matches hosted in APAC
account for 5 of the 12 timeouts and 11 of the 27 drops, while making up about
a quarter of the sessions. The one NA match with recorded play had no timeouts
or drops in 19 sessions.

**What we would investigate.**

| Match | What stands out | Why it is worth a look |
|---|---|---|
| **Match 2** (APAC, ranked) | 3 timeouts in 16 sessions: **18.8%**, almost four times normal. A quarter of all timeouts on the platform. | The three timeouts hit three different players in January, March and December. This is a recurring fault, not one bad evening. It is the clearest single target. |
| **Match 11** (APAC, ranked) | Only 1 timeout, but 4 platform-side drops in 15 sessions: **26.7%**, more than twice normal. The lowest average score on the platform. | It has a timeout, a server restart and two client crashes. Its low score comes from abandoned sessions scoring zero, not from weaker players. |
| **Match 3** (OCE, casual) — watch only | 2 timeouts in 13 sessions: 15.4%. | Too few sessions to call yet. Keep it on watch and recheck once it passes 15 sessions. |

Matches 2 and 11 are both hosted in APAC. The first question for the server
operations team is whether they share infrastructure.

**Two cautions before acting on these numbers.**

- **Average scores here are partly failure counts.** Every abandoned session
  scores zero, so a match with more drops will always look like it has weaker
  players. We would not use average score to judge players or matches until
  abandoned sessions are separated out.
- **A match's listed player count is not attendance.** One match listed for 4
  players recorded 21 sessions. Any payout or quota based on that field should
  be checked against what was actually recorded.

None of this changes last time's recommendation: the payout was correct to
release. What these numbers support is a targeted look at two APAC matches,
not a platform-wide response.
