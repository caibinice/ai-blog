---
title: Cherry-pick best practices: taming branches across multi-site deployments
excerpt: When the same system ships to several factories separately, reusing a feature across sites by merging branches into one another eventually spirals out of control. My rule is to let cherry-pick travel a single path — every feature first collapses into one clean commit on the mainline, then gets picked into whichever site needs it.
---

Shipping the same system to several factories separately is something I’ve refined over a lot of real projects. The same Java + Vue codebase has to land at different sites, and each factory keeps its own deployment branch with different device addresses, line configurations, and database scripts. Yet features are heavily shared — a logging platform one factory has polished is something factories B and C will probably want too.

The whole problem hides in that word, *want*. When you move a feature from one factory to another, the laziest idea is to merge the branch across — and that’s exactly the move that plants landmines. This post is about the discipline I eventually settled on: for reusing features across sites, let `cherry-pick` travel a single path.

## First, sort out the three kinds of branches

Before touching anything, you have to admit the branches in this repo are not peers. They come in three kinds:

- **The mainline `prod_main`**: holds the clean, reusable feature commits every factory can share. It maps to no single site — it’s the clearing house for shared work.
- **Deployment branches `prod_factory_a`, `prod_factory_b`, …**: what each factory actually runs on-site, carrying its own site-specific config.
- **Retired root branches** (an old `main`, `prod`, and the like): no longer a baseline for development, picking, or release — kept only as history.

One trap deserves its own sentence: some deployment branches have `main` in the name (say a factory’s `factory_c/main`). It is **not** the root branch and **not** the mainline — it’s just that factory’s deployment branch. Names mislead; roles don’t.

The whole workflow in one line: **a cross-site feature travels a single path — source deployment branch → (collapsed into one commit on the mainline) → target deployment branch.**

## The one rule: deployment branches never merge into each other

The most intuitive — and most dangerous — move is to merge the branch that carries the finished feature straight into the target site:

```
# Anti-pattern, don't do this
git switch prod_factory_b
git merge origin/prod_factory_a
```

The moment you do, factory A’s device calls, site-specific config, and init scripts pour into factory B alongside the one feature you actually wanted. It compiles fine right then; the problem usually surfaces weeks later, on-site, when a hard-coded device address turns out to have hitched a ride. A deployment branch represents *what this factory is actually running right now* — branches like that simply should not merge into each other.

The correct path is two stages: first pick, filter, and collapse the source factory’s commits into one clean commit on the mainline; then let the target factory pick that single commit.

![Two-stage flow: source deployment branch → (cherry-pick -n several commits + filter) → prod_main one clean commit → (cherry-pick -x) → target deployment branch](/images/cherry-pick-flow.svg)

## One feature, one commit on the mainline

In its home factory a feature usually grew piecemeal: create the module, add a service and mapper, tweak a controller, patch some config along the way, and probably mix in a call that only that factory needs. Copying that commit history is pointless and unreusable.

So when it enters the mainline, I don’t carry the history — only the result:

```
git switch prod_main
git cherry-pick -n <source-commit-1> <source-commit-2> <source-commit-3>
```

`-n` is `--no-commit`: it lays all those changes out in the working tree without rushing to commit, handing the *which of this actually stays?* decision back to me. Then comes the part that really takes time — reading the diff file by file, rolling back anything site-specific, deleting directories that don’t belong, trimming the dependency list to the minimum wiring. Only once it’s filtered and the build and tests pass do I fold it into one commit:

```
git commit -m "feat(common): add log platform"
```

At that point the feature has exactly one clean commit hash on the mainline. The payoff is concrete: the branch count stops ballooning; which factory adopted the feature and when is a matter of reading the mainline history; and rolling back is rolling back that one commit.

## Stage one: from factory A onto the mainline

Before I start, I have a 30-second habit: `git status` to confirm a clean tree, `git fetch origin --prune` to refresh remotes, confirm I’m standing on `prod_main` and not some root branch, and finally **note the current `prod_main` SHA** as a rollback point.

Then switch to and update the mainline:

```
git fetch origin --prune
git switch prod_main
git pull --ff-only origin prod_main
```

On the source branch, work out exactly which commits to carry — don’t judge by commit titles, read the file list and diff:

```
git log origin/prod_factory_a --oneline --decorate
git show --stat <source-commit>
```

Check three things: which files these commits touched, whether any factory-specific device address or interface tagged along, and whether the commits depend on one another. Once that’s clear, `cherry-pick -n` all of them into the working tree in order, then filter — a step where a GUI diff is easiest: keep what’s reusable, roll back factory-specific files, delete new directories that shouldn’t be here, and leave only the necessary module declarations and dependencies in the POMs. Run the build and tests, confirm the working tree holds only what this feature should, then fold it into that **one** commit and push.

## Stage two: factory B picks from the mainline

The second stage is far lighter, because the mainline already holds a filtered, tested, clean commit:

```
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
git cherry-pick -x <mainline-feature-SHA>
```

`-x` writes the source commit hash into the new commit message, so the feature’s origin stays one glance away. If factory B needs extra adaptation, **make that a separate commit** — never fold it back into the shared mainline commit. Build, test, then push.

## A full case: moving the logging platform to factory B

Abstractions feel hollow, so here’s a real example I’ve actually done (details anonymized).

Factory A built a logging platform on-site, and now factory B wants it too. The relevant changes are scattered across three commits on the source branch:

| Source commit (example) | What it does | Why it can’t be carried commit-by-commit |
|---|---|---|
| `a1c9f0e` | Consolidates log management into its own module | Also moved several old module files and touched multiple POMs |
| `b2d47a1` | Builds the module’s core | Mixes in an unfinished starter and factory-A-specific calls |
| `c3e8b90` | Moves service, mapper, entities into the module | Also touches the thread pool, on-site services, and old module files |

So you `-n` them together first, then filter. I list up front what goes into the mainline and what stays firmly out:

![Case filtering: into prod_main go the log module and minimal POM wiring; excluded are the standalone starter, factory-specific calls, peripheral changes, and frontend scripts](/images/cherry-pick-selection.svg)

**Allowed into `prod_main`**: the module directory `log-platform/**`, its two backend controllers, the module’s config class, and the minimal module declarations and dependency wiring across the three POMs.

**Firmly excluded**: the standalone `log-platform-starter` module (and its `<module>` declaration in the root POM), factory A’s work-order and device calls, unapproved peripheral changes like the thread pool, and the frontend pages and database init scripts.

Stage one — collapse the three commits onto the mainline, filter, build, and fold into one commit:

```
git switch prod_main
git pull --ff-only origin prod_main
git cherry-pick -n a1c9f0e b2d47a1 c3e8b90
git restore --staged .
# In the IDE: roll back files outside the whitelist, delete extra dirs, trim POMs to minimal wiring
git status --short          # confirm only whitelisted content remains
mvn -pl log-platform -am clean test
git add log-platform
git add -p pom.xml          # take only the POM fragments you need
git commit -m "feat(common): add log platform"
git push origin prod_main
```

Note the SHA this produces — that’s the logging platform’s one and only shared commit on the mainline.

Stage two — factory B picks that single commit, runs the tests, then pushes:

```
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
git cherry-pick -x <mainline-SHA-from-above>
mvn -pl log-platform -am clean test
git push origin prod_factory_b
```

The three branches end up exactly where they should: factory A keeps its original commits and adaptations; the mainline gains one clean logging-platform commit; factory B’s branch has picked that single commit, plus its own adaptation commit if needed. When factory C wants it later, that’s just picking the same one commit from the mainline again.

## Conflicts and rollbacks

`cherry-pick` hitting a conflict is routine. Resolve it, `git add`, then `git cherry-pick --continue`; to abandon the pick entirely, `git cherry-pick --abort` returns you to a clean state.

Backing out a mistake splits two ways. **Not pushed yet**: `git reset --hard <the SHA you noted first>`, then `git clean -nd` to preview and, once you’re sure, `git clean -fd` to clear the extra files — which is exactly why I always save a SHA before starting. **Already pushed to the mainline**: don’t force-push and don’t rewrite shared history; make an honest reverse commit with `git revert <bad-commit>`. If other factories already picked the bad commit, each of them reverts too.

## Commit messages that stay traceable

I classify commit messages by purpose so the mainline history explains itself: shared features as `feat(common): ...`, a factory’s adaptation as `feat(factory-b): ...`, shared fixes as `fix(common): ...`. No more “update code” or “tweak feature” — the kind of message nobody can decode a month later.

## To close

The expensive part of working across sites was never writing the feature. It’s failing, months later, to explain why a particular piece of code is even in this factory. Used well, `cherry-pick` is really a discipline: keeping every shared feature to a single clean, traceable, one-command-revertible commit on the mainline is just saving your future self the cost of that explanation.
