---
title: Branch Governance with Cherry-Pick in Multi-Factory Deployments
excerpt: Managing multi-site code deployments: using single-path cherry-pick workflows to distill features into atomic trunk commits before promoting to factory deployment branches.
---

When deploying a unified enterprise system (based on Java + Vue architecture) across multiple manufacturing plant sites, each facility maintains a dedicated production branch containing plant-specific PLC/hardware addresses, production line routing, and localized SQL initialization scripts. Simultaneously, core platform capabilities (such as unified logging systems and analytical reporting) frequently need to be shared across multiple facilities.

Executing `git merge` directly between factory deployment branches introduces serious risks, as site-specific configurations and unvetted local adaptations can inadvertently bleed into other production environments. To ensure production stability and code traceability, this article outlines a two-stage branch governance model built upon disciplined `cherry-pick` workflows.

## Branch Hierarchy and Role Definitions

Within a multi-branch repository, branches fulfill distinct operational roles:

- **Common Trunk Branch (`prod_main`)**: Houses standardized features and reusable components, serving as the clean integration baseline for all shared code;
- **Factory Deployment Branches (`prod_factory_a`, `prod_factory_b`, ...)**: Represent the active production runtime for each specific site, holding environment-specific configurations and localized adapters;
- **Archived Base Branches**: Legacy root branches preserved strictly for historical reference, not used for daily development or releases.

The governing rule for cross-site feature reuse is: **Never merge factory deployment branches directly into one another. All shared capabilities must first be consolidated into a single atomic commit on `prod_main`, and subsequently cherry-picked into target factory branches.**

```text
Source Factory Branch (prod_factory_a)
       │
       ▼ (cherry-pick -n multiple commits & clean site-specific code)
Common Trunk (prod_main) ───> Consolidated into 1 atomic commit
       │
       ▼ (cherry-pick -x with provenance tracking)
Target Factory Branch (prod_factory_b)
```

## Prohibiting Direct Cross-Branch Merges

In multi-site architectures, the following pattern represents a critical operational risk:

```bash
# High-risk anti-pattern: Never merge directly between factory branches
git switch prod_factory_b
git merge origin/prod_factory_a
```

Direct merging imports Factory A's hardware endpoints, local middleware hosts, and site-specific SQL updates directly into Factory B. These pollutions often pass compilation unnoticed, only to cause runtime hardware connection failures in production.

The standardized two-stage workflow decouples feature abstraction from local adaptation:

![Two-stage workflow: source factory branch → (cherry-pick -n + filter) → prod_main single clean commit → (cherry-pick -x) → target factory branch](/images/cherry-pick-flow.svg)

## Atomic Feature Consolidation on Trunk

Feature development on a source factory branch typically accumulates multiple fragmented commits (initial implementation, local debugging, interface tweaks, etc.). When promoting this work to the common trunk, the goal is to extract the functional logic and consolidate it into a single clean commit.

The operational sequence is:

```bash
git switch prod_main
git pull --ff-only origin prod_main
# Load multiple commits from the source branch into the staging area without committing
git cherry-pick -n <source_commit_1> <source_commit_2> <source_commit_3>
```

Using `cherry-pick -n` (`--no-commit`) stages file changes directly in the working tree, allowing granular inspection:
1. Revert all plant-specific configuration files and hardware client classes;
2. Remove unverified peripheral scripts and test mocks;
3. Clean Maven `pom.xml` descriptors, retaining only minimal module references and dependencies;
4. Execute unit tests and local builds;
5. Commit the final clean state as a single atomic commit:

```bash
git commit -m "feat(common): add log platform"
```

This atomic structure keeps trunk history linear and clean, simplifying downstream cherry-picks and future rollbacks.

## Stage 1: Distillation from Source Factory to Trunk

When promoting a capability from a source factory branch to the trunk:

1. **Workspace Verification**: Ensure a clean working tree, fetch remote references, and record the current `prod_main` HEAD SHA as a rollback point;
2. **Commit Audit**: Review the source branch commit log and file diffs to map out affected files and dependency boundaries:

```bash
git log origin/prod_factory_a --oneline --decorate
git show --stat <source_commit_sha>
```

3. **Change Filtering**: Execute `cherry-pick -n` and use IDE visual diff tools to discard site-specific logic, ensuring only generic code remains;
4. **Validation and Push**: Run module-level builds and test suites before pushing to remote `prod_main`.

## Stage 2: Selective Promotion to Target Factory Branches

Once the feature is established as a clean commit on `prod_main`, promoting it to target factory branches is straightforward:

```bash
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
# Use -x flag to preserve source commit provenance
git cherry-pick -x <trunk_feature_commit_sha>
```

The `-x` flag automatically appends `(cherry picked from commit ...)` to the commit message, establishing clear traceability. If Factory B requires local configuration adjustments or specialized beans, **these must be committed as a separate, distinct adaptation commit**, preventing local overrides from polluting trunk artifacts.

## Real-World Case: Promoting the Log Platform to Factory B

Consider a logging module developed at Factory A that needs to be deployed to Factory B. The original changes are spread across three commits:

| Source Commit | Commit Content | Non-Reusable Modifications Included |
|---|---|---|
| `a1c9f0e` | Core logging module structure | Relocated legacy business files, modified root POM |
| `b2d47a1` | Ingestion service and configurations | Contained an unfinished starter and Factory A hardware hooks |
| `c3e8b90` | Query controllers and mappers | Altered local thread pools and site-specific SQL scripts |

To migrate safely, establish an explicit file inclusion whitelist:

![Case study selection: entering prod_main is the log module and minimal POM wiring; excluded are the standalone starter, site-specific calls, peripheral changes, and frontend scripts](/images/cherry-pick-selection.svg)

- **Permitted for `prod_main`**: `log-platform/**` directory, generic controllers, module configuration classes, and minimal root POM module wiring;
- **Strictly Excluded**: `log-platform-starter` module, Factory A work order reporting hooks, thread pool overrides, frontend routing, and local schema DDL scripts.

Execution commands:

```bash
git switch prod_main
git pull --ff-only origin prod_main
git cherry-pick -n a1c9f0e b2d47a1 c3e8b90
git restore --staged .
# Discard non-whitelisted files and clean POM wiring
git status --short
mvn -pl log-platform -am clean test
git add log-platform
git add -p pom.xml
git commit -m "feat(common): add log platform"
git push origin prod_main
```

Promotion to Factory B:

```bash
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
git cherry-pick -x <trunk_commit_sha>
mvn -pl log-platform -am clean test
git push origin prod_factory_b
```

## Conflict Resolution, Rollbacks, and Commit Standards

### 1. Conflict Resolution
When conflicts occur during `cherry-pick`, resolve them via standard 3-way merge tools, stage resolved files with `git add`, and proceed with `git cherry-pick --continue`. To abort the operation cleanly, run `git cherry-pick --abort`.

### 2. Rollback Standards
- **Unpushed Local Rollback**: Execute `git reset --hard <pre_operation_sha>` followed by `git clean -fd` to remove untracked artifacts;
- **Pushed Trunk Rollback**: Never force-push (`--force`) over shared trunk history. Instead, use `git revert <commit_sha>` to create an explicit inverse commit.

### 3. Commit Message Conventions
Structured prefixes clarify commit scope:
- `feat(common): ...`: Reusable trunk features
- `fix(common): ...`: Common bug fixes on trunk
- `feat(factory-a): ...`: Site-specific adaptations

This disciplined Cherry-pick workflow guarantees clean separation between shared assets and localized runtime environments, significantly reducing maintenance overhead across distributed manufacturing deployments.
