# UI Extensions: Child Resource Activation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `matchOnAncestors` opt-in to Resource Tab extensions so they activate when the selected resource is a descendant of a resource matching the extension's group/kind, while preserving full backwards compatibility.

**Architecture:** Extend `registerResourceExtension` opts with `matchOnAncestors?: boolean`. When true, `getResourceTabs` also matches extensions when any ancestor of the selected node matches group/kind. Add optional `tree` and `selectedNode` params to `getResourceTabs`; when provided, ancestor traversal runs. Use `parentRefs` to walk the tree; resolve parents from `nodes` and `orphanedNodes`.

**Tech Stack:** TypeScript, React, minimatch, Argo CD UI models (ApplicationTree, ResourceNode, ResourceRef)

**Design doc:** `docs/plans/2025-02-24-ui-extensions-child-resource-activation-design.md`

---

## Task 1: Add `hasAncestorMatching` helper

**Files:**
- Create: `ui/src/app/shared/services/extensions-service-helpers.ts`
- Modify: `ui/src/app/shared/services/extensions-service.ts`

**Step 1: Create helper module**

Create `extensions-service-helpers.ts` with:
- `nodeKey(ref: {group: string; kind: string; namespace: string; name: string}): string` — returns `[group, kind, namespace, name].join('/')`
- `hasAncestorMatching(node: ResourceNode, tree: ApplicationTree, group: string, kind: string): boolean` — builds `nodeByKey` from `tree.nodes` and `tree.orphanedNodes`, walks `node.parentRefs` recursively, returns true if any ancestor matches via minimatch; tracks visited keys to avoid circular refs; skips missing parents

**Step 2: Update getResourceTabs in extensions-service**

Import the helper. Change `getResourceTabs(group, kind)` to `getResourceTabs(group, kind, tree?, selectedNode?)`. When `tree` and `selectedNode` provided, for extensions with `matchOnAncestors === true`, also include if `hasAncestorMatching(...)` (wrap in try/catch). Filter: include if direct match OR (matchOnAncestors && ancestor match).
- Builds a `nodeByKey` map from `tree.nodes` and `tree.orphanedNodes`
- Walks `node.parentRefs` recursively, resolving each parent via `nodeByKey`
- Returns true if any ancestor matches `minimatch(ancestor.group, group) && minimatch(ancestor.kind, kind)`
- Tracks visited keys to avoid circular refs
- Returns false if parent not found (skip and continue)

Update `getResourceTabs(group, kind, tree?, selectedNode?)`:
- When `tree` and `selectedNode` are provided, for each extension with `matchOnAncestors === true`, also include if `hasAncestorMatching(selectedNode, tree, ext.group, ext.kind)` (wrap in try/catch, fallback to direct match only on error)
- Filter logic: include extension if direct match OR (matchOnAncestors && ancestor match)

**Step 2: Run existing tests**

Run: `cd ui && npm test -- --testPathIgnorePatterns=node_modules --passWithNoTests 2>/dev/null || true`
Expected: No new failures (extensions-service has no existing tests)

**Step 3: Commit**

```bash
git add ui/src/app/shared/services/extensions-service.ts
git commit -m "feat(ui): add ancestor matching support to getResourceTabs"
```

---

## Task 2: Extend registerResourceExtension opts and ResourceTabExtension interface

**Files:**
- Modify: `ui/src/app/shared/services/extensions-service.ts`

**Step 1: Update registerResourceExtension and interface**

- Change `opts?: {icon: string}` to `opts?: {icon?: string; matchOnAncestors?: boolean}`
- Add `matchOnAncestors?: boolean` to `ResourceTabExtension` interface
- In `registerResourceExtension`, pass `matchOnAncestors: opts?.matchOnAncestors` into the extension object

**Step 2: Commit**

```bash
git add ui/src/app/shared/services/extensions-service.ts
git commit -m "feat(ui): add matchOnAncestors opt to registerResourceExtension"
```

---

## Task 3: Update resource-details call site

**Files:**
- Modify: `ui/src/app/applications/components/resource-details/resource-details.tsx`

**Step 1: Pass tree and selectedNode to getResourceTabs**

Find the call around line 236:
```typescript
const extensions = selectedNode?.kind ? services.extensions.getResourceTabs(selectedNode?.group || '', selectedNode?.kind) : [];
```

Change to:
```typescript
const extensions = selectedNode?.kind ? services.extensions.getResourceTabs(selectedNode?.group || '', selectedNode?.kind, tree, selectedNode) : [];
```

**Step 2: Run tests**

Run: `cd ui && npm test -- --testPathIgnorePatterns=node_modules 2>&1 | head -80`
Expected: Tests pass

**Step 3: Commit**

```bash
git add ui/src/app/applications/components/resource-details/resource-details.tsx
git commit -m "feat(ui): pass tree and selectedNode to getResourceTabs for ancestor matching"
```

---

## Task 4: Add unit tests for ancestor matching

**Files:**
- Create: `ui/src/app/shared/services/extensions-service-helpers.test.ts`

**Step 1: Write tests for hasAncestorMatching**

Create test file that imports `hasAncestorMatching` from `extensions-service-helpers` and tests:
- Returns true when direct parent matches group/kind
- Returns true when ancestor two levels up matches
- Returns false when no ancestor matches
- Returns false when node has no parentRefs
- Handles missing parent in tree (skip, continue)
- Handles circular parentRefs (track visited, return false to avoid infinite loop)
- Includes orphanedNodes when building nodeByKey

Use minimal ResourceNode and ApplicationTree fixtures (group, kind, namespace, name, parentRefs, nodes, orphanedNodes).

**Step 2: Run tests**

Run: `cd ui && npm test -- extensions-service-helpers.test.ts -v`
Expected: All tests pass

**Step 3: Commit**

```bash
git add ui/src/app/shared/services/extensions-service-helpers.test.ts
git commit -m "test(ui): add unit tests for hasAncestorMatching"
```

---

## Task 5: Update UI extensions documentation

**Files:**
- Modify: `docs/developer-guide/extensions/ui-extensions.md`

**Step 1: Document matchOnAncestors**

In the Resource Tab Extensions section, update the `registerResourceExtension` signature and opts:
- Add `matchOnAncestors?: boolean` to opts
- Add 1–2 sentence description: when true, extension also activates when the selected resource has an ancestor matching group/kind
- Add a short example showing Rollout extension with `matchOnAncestors: true` so it shows for Rollout, ReplicaSet, and Pod

**Step 2: Commit**

```bash
git add docs/developer-guide/extensions/ui-extensions.md
git commit -m "docs: document matchOnAncestors for Resource Tab extensions"
```

---

## Execution Handoff

Plan complete and saved to `docs/plans/2025-02-24-ui-extensions-child-resource-activation.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?
