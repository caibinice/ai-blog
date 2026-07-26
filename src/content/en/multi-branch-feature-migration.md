---
title: One feature, one commit: taming branches across multi-site deployments
excerpt: When the same system ships to several factories separately, I stopped letting deployment branches merge into one another. Instead, every reusable feature first collapses into a single clean commit on the mainline, then gets cherry-picked into whichever site needs it.
---

Shipping the same system to several factories separately is a class of trouble I’ve walked into more than once. Every site has its own deployment branch, with different device addresses, line configurations, and database scripts. Yet plenty of features are common — a logging platform one factory has polished is something the others will probably want too. The whole mess hides inside that word: *want*.

## Deployment branches should never merge into each other

The most intuitive move is to merge the branch that carries the finished feature straight into the target site:

```
git switch prod_factory_b
git merge origin/prod_factory_a
```

The moment you do that, factory A’s device calls, site-specific config, and init scripts all pour into factory B alongside the one feature you actually wanted. It compiles fine right then; the problem tends to surface weeks later, on-site, when some hard-coded address turns out to have hitched a ride. A deployment branch represents *what this factory is actually running right now* — and branches like that should never merge into one another.

The one rule I eventually set for myself: a cross-site feature travels a single path — source branch → one commit on the mainline → target branch. No temporary branches in between. That clean commit on the mainline (I call it `prod_main`) is the only unit of transfer.

## Let the feature collapse into a single commit on the mainline

In its home factory a feature usually grew piecemeal: create the module, add a service, tweak a controller, patch some config along the way, and probably mix in a call that only that factory needs. Copying that history wholesale is pointless. What I do is pull the commits I need into the working tree first — without committing:

```
git switch prod_main
git cherry-pick -n <commit1> <commit2> <commit3>
```

`-n` is `--no-commit`: it lays the changes out in the working tree but hands the *should this really go in?* decision back to me. Then comes the part that actually takes time — reading the diff file by file, rolling back anything site-specific, deleting directories that don’t belong, trimming the dependency list to the minimum wiring. Once it’s filtered and the build and tests pass, I fold it into one commit:

```
git commit -m "feat(common): add log platform"
```

At that point the feature has exactly one clean commit hash on the mainline.

## Every other factory just cherry-picks that one commit

Whichever site wants it pulls that single commit across:

```
git switch prod_factory_b
git cherry-pick -x <mainline-commit-SHA>
```

`-x` records the source commit hash in the new commit, so the origin stays traceable later. If the target site needs extra adaptation, that goes in as a separate commit — never folded back into the shared one on the mainline.

What actually makes this workflow easier on me isn’t its elegance; it’s that it keeps complexity pinned down. The branch count stops ballooning, every common feature maps to a commit you can recognize at a glance, and who adopted it and when is a matter of reading the history. Rolling back is rolling back that one commit — nothing more.

## When something goes wrong

If you haven’t pushed yet, `git reset --hard` back to the SHA you noted before you started — which is exactly why I always save one first. If it’s already pushed to the mainline, don’t force-push and don’t rewrite shared history; just make an honest reverse commit with `git revert`. If other factories already picked up the bad commit, each of them reverts it too.

The expensive part of working across sites was never writing the feature. It’s failing, months later, to explain why a particular piece of code is even in this factory. Keeping each feature to a single commit is really just saving your future self the cost of that explanation.
