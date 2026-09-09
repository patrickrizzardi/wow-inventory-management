# Corpses

Failure patterns that proved they recur. An entry earns its place only after the same class
appears a second time in a loop — never from a self-narrated near-miss.

---

## C1 — Hand-written completeness and identity claims

**First seen:** plan `2026-09-07-audit-remediation`, Phase 1, review rounds 1 and 2. **Survived its
own remedy in round 3** — see "Why vigilance is not the fix" below.

**The class.** A comment, doc-string or user-facing string asserts that a set is *complete*
("every setting that decides which items auto-sell", "one boundary, two consumers"), that two
things are the *same* ("ONE retry budget shared by both paths"), or that a live external system
*behaves* a certain way ("selling cannot be undone", "buyback lasts until you close the merchant
window"). Nothing checks the claim. The claim rots, or was never true.

**Instances, five across two rounds.** "one boundary, two consumers" (were three) · retry budget
"max 10" (was 11) · "tokens carry no vendor sell price" (unverifiable offline) · mail-rule comment
labelled "third priority" after the same diff renumbered it fourth · "every setting that decides
WHICH items auto-sell" (omitted mail rules).

**Why it matters, not just tidiness.** The fifth instance was an asset-loss defect, not a stale
comment. `_AutoSellFingerprint` hand-enumerated three settings tables while claiming to cover all
of them; mail-rule settings decide auto-sell scope and were absent, so unticking Mail Helper's
master enable carried an old consent forward and vendored every item the rule was protecting,
unattended. The false comment and the defect were the same act.

**Producer.** Claims about a *property of a set* are written by hand and verified by nobody. The
adjacent code drifts; the sentence does not. This is distinct from an ordinary stale comment —
local intent comments age fine. Completeness and identity claims are the ones that rot, because
they assert something about code the author is not looking at.

**The rule that kills it.** Derive the claim or don't assert it. A set that must be complete is
computed from the thing it must match, never listed twice. A property that cannot be derived is
either verified against the live system and cited, or written without the specific assertion.
A comment describing *why this line exists* is fine; a comment describing *what all the other
code does* is a liability.

**Why vigilance is not the fix.** Round 3's remedy was an executor hand-auditing the comments it
had just written, and rewriting seven that carried the shape. That worked on those seven — and the
class still recurred four more times in the same round, because a hand-run audit over
"the comments I wrote" is itself a hand-maintained claim over a set, scoped to precisely the subset
that cannot contain the survivor. The one that lived was ten lines above the block being rewritten,
unchanged and therefore out of scope: *"SellJunk() has its own retry logic for pending items (max 10
attempts)"* — both halves false, and it is instance #2 from the list above, still alive after being
named in this very file.

Three more landed the same round, all written after this entry existed: a docstring claiming a
`started` return proves a click sold something (it proves a queue was built); a tooltip comment
hand-restating `ShouldAutoSell`'s priority order, already missing its mail-rule tier — the exact
shape whose fifth instance was the asset blocker; and a "colour is stored once" claim with three
other files sourcing it elsewhere.

**Read that as the producer's real depth.** Asking an author to be careful about a class of claim
is a claim about a set the author maintains by hand. The disease eats its own cure. Only a
mechanical check — derivation, a test that fails when the claim goes false, or deleting the
sentence — actually removes an instance.

**Checkable.** Every instance of the class dies when no hand-maintained list claims completeness
over a set that some other function actually reads.

**This section described a mechanism that no longer exists — corrected 2026-09-08, and the
correction is itself the eighth instance.** Round 4 built `IM:AuditFingerprintScope` and this entry
described it in the present tense. Round 5 deleted that function, and this file became its only
surviving reference in the tree: a hand-written claim about code the author was not looking at,
sitting in the registry whose entire job is catching exactly that. Left as evidence rather than
quietly rewritten. What is actually true now:

- The consent fingerprint no longer hashes the database and subtracts. There is no exclusion list
  and no audit. It hashes the settings `Filters:ShouldAutoSell` actually reads, recursively and
  wholesale, so a new key inside one of those tables is covered the moment it exists.
- What holds the set honest is a mutation battery, not a sentence: each setting is moved and the
  fingerprint must move **iff** some item's verdict can move. It was validated by reintroducing two
  historical defects — round 2's unhashed mail rules and round 3's whole-`mailHelper` hash — which
  fail it loudly in opposite directions.
- **Residual, stated so nobody reads more into this than it earns:** the battery is a
  hand-maintained enumeration one level up. A brand-new top-level `db.global` table that
  `ShouldAutoSell` learns to read, with no battery case added, is hashed by nobody and caught by
  nobody. And five filter tiers — soulbound, warbound, transmog, toy, equipment-set — are stubbed
  inert in the harness, so the iff is *vacuously* true over them.
- `Modules/TooltipInfo.lua`'s JUNK line asks `Filters:ShouldAutoSell` for the verdict instead of
  restating its priority order. There is no order to keep in step any more.
- `Core.lua`'s "colour is stored once" and "no literal restates it" are gone, replaced by what the
  table is for; the three files that source a quality colour elsewhere are named rather than
  contradicted.
- The offline suite loads the **real** `Core.lua`, `Database.lua`, `Filters.lua`, `AutoSell.lua`
  and `MailHelper.lua`, and answers the real confirm dialog, so the claims it locks are executable.

**The claim above was checked by a reviewer and came back weaker than written.** Round 4's
"eight guards, a named failure for each" was the author's own count. An independent mutation pass
found five survivors, two of them load-bearing: the slot-identity check before the vendor call
(its branch fires zero times across the whole suite) and *"a manual sale grants nothing"* — the
owner's own ruling, asserted three times in comments and locked by no assertion at all. Both were
closed afterwards. **Read that as the rule, not the anecdote: a suite's coverage claim written by
whoever wrote the suite is the same class of hand-written assertion this entry exists for.** The
only version worth believing is one where someone else deleted the guard and watched it go red.

---

## C2 — A guard consulted by an enumerated list of callers instead of at the chokepoint

**First seen:** plan `2026-09-07-audit-remediation`, Phase 1, review rounds 5 and 7. Both instances
were reachable unattended sales of items the user believed protected.

**The class.** An authorization check lives at the sites that *call* the dangerous operation rather
than inside the operation itself. Correctness then depends on a list of call sites that somebody
maintains by hand — and the list is invisible, because it is not written anywhere. It is simply
"the places we thought of."

**Instance 1, round 5.** `_visitBoundToApproval` was written by `MERCHANT_SHOW` and read only by
`FinishSelling`'s sweep, while `MERCHANT_SHOW`'s own `SellJunk(nil, true)` never consulted it. Two
reviewers found it and both prescribed fixing the flag's lifetime. A third reviewer found the leg
they missed: the sweep the flag blocks is a strict *subset* of what the unguarded path sells, so
the mechanism delivered none of its stated property.

**Instance 2, round 7 — the fix for instance 1 grew the third path itself.** The remedy was "one
authority every sale-start path consults," implemented at the call sites. The same rounds then
added item-data waiter machinery whose retry re-enters `SellJunk` with no gate and no approved
list. A grant withdrawn mid-wait — the player clears their whitelist while a retry is armed — still
sold. Reproduced against the real files, not argued from spec.

**Producer.** "Every path" is a completeness claim over a set of callers, held in someone's head.
It is C1's disease with executable consequences: C1 rots a sentence, C2 rots a guard. And it has
the failure mode that makes it hard to see — **each new path is added by someone solving a
different problem**, who has no reason to know an unrelated invariant depends on their code
consulting something first.

**The rule that kills it.** Put the check where the dangerous thing happens, not where it is asked
for. The chokepoint is the function that cannot be bypassed — here, the one place a queue is built
and `_isSelling` is set. A caller-side check is a convention; a chokepoint check is a property.

**Checkable.** Every instance dies when adding a new caller cannot bypass the guard, because the
guard is downstream of every caller. Test for it by writing the bypass: call the dangerous
function directly, from a path nobody sanctioned, and confirm it refuses.

**Note for whoever reads this next.** Round 5's conductor — me — accepted "one authority every
sale-start path consults" as a producer-level fix and declared the round clean. It was a
caller-side fix wearing a chokepoint's language. Two rounds later the same bug came back through a
door that did not exist when the list was written. If a proposed fix's correctness rests on
enumerating callers, it has not reached the producer yet.

---

## C3 — Staging early, so the committed content is not the tested content

**First seen:** plan `2026-09-07-audit-remediation`, Phase 1, rounds 7 and 9. Caught both times
before a commit; would have shipped wrong content both times.

**The class.** A file is `git add`ed mid-round to satisfy some "make it tracked" instruction, then
edited again in the same round or a later one. The index now holds one version and the working
tree another. Every test, every gate, every reviewer reads the **working tree**. The commit takes
the **index**. Nothing in the ordinary flow compares them, so the divergence is invisible right up
until it is permanent.

**Instance 1, round 7.** The harness was staged with its pre-move paths and a floating image tag,
then fixed in the working tree. `git status` said `AM`. The suite ran 149/0 against content that
was not what a commit would have taken; the staged copy still pointed at a directory that no
longer existed. The gate caught it and returned red.

**Instance 2, round 9.** Same two files, same shape, 315 lines of divergence. This time the gate
printed the `AM` in a status dump and still returned **green** — the check that caught it in round
7 was scoped to that round's specific question and did not generalise. Caught by the conductor
reading the status output, which is not a mechanism.

**Producer.** Staging is a commit-time action performed at edit time. Nothing else in the workflow
reads the index, so it is a second copy of the truth that no reviewer, test or gate is looking at.
"Track this file" was heard as "stage it now" — but a file can be *intended* for a commit without
being staged for one.

**The rule that kills it.** Stage nothing until the commit, and re-derive the pathspec from
`git status --porcelain` in the same breath as `git commit`. Where something must be staged early,
`git diff --name-only` (index vs worktree) is the check, and it belongs in the gate, not in a human
reading a status dump.

**Checkable.** Every instance dies when no `AM` state survives into a commit — equivalently, when
`git diff --name-only` is empty at the moment `git commit` runs. A gate that prints status without
asserting on it does not count; round 9 is the proof.
