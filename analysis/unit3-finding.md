# Finding: the ranked network-timeout rate is about 5%, not about half

**To:** Live Ops dashboard team
**From:** Trust and Data
**Re:** The network-timeout figure behind the ranked-mode rewards freeze

Your dashboard reported that about half of ranked match sessions end in a
network timeout, and leadership froze this quarter's ranked-mode rewards because
of it. The data does not support that number. Of the 173 sessions recorded in
ranked matches, 9 ended in a network timeout. Leaving out the 7 sessions where
the player chose to quit, as the dashboard intends to, the rate is 9 out of 166,
or **5.4%**. Across every match, ranked and casual, it is 12 out of 200 (6%).
Most sessions, 156 of 200, finished normally. Another 10 are marked "contested",
meaning the result is under review. They are disputes, not connection failures,
and should not be counted as timeouts.

The error comes from how the dashboard set aside voluntary quits. Each session
has a "disconnect reason" that is filled in only when a player drops out. When a
session finishes normally, the reason is left blank. The dashboard's rule was
meant to keep every session except voluntary quits. Instead, it also threw away
every session with a blank reason, because the database treats a blank as "can't
tell" and quietly excludes it rather than raising an error. That removed 166
normal sessions from the count without any warning. Ranked matches were left
with just 20 sessions, every one of them a disconnect of some kind. Nine of those
20 were timeouts, so the dashboard showed 45%, which reads as "about half". When
we rebuilt the calculation with the blank reasons handled correctly, the same 9
timeouts sat in a group of 166 sessions, and the rate fell to 5.4%. The
dashboard's figure looked believable because the query ran without errors and
produced a plausible-looking percentage. Nothing on the screen showed that most
of the sessions were missing.

We recommend lifting the freeze and paying ranked-mode rewards on the normal
schedule. If leadership wants a closer look at the timeouts themselves, they
involve 8 players and 9 sessions. Those can be reviewed one by one without
holding up everyone else's payout. The dashboard should switch to the corrected
calculation, which we have provided. Going forward, every rate it reports should
also be checked against the full session total: the sessions counted plus the
sessions excluded must add up to all sessions. That one check would have caught
this problem the day the dashboard was built.
