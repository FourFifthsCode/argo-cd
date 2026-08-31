# UI Extensions: Child Resource Activation — Design

**Date:** 2025-02-24

## Summary

Expand Resource Tab UI extensions to support activation when the selected resource is a descendant of a resource matching the extension's group/kind. Maintain full backwards compatibility with existing extensions.

## Requirements (Validated)

- **Activation mode:** Extension activates when the selected resource has an ancestor matching the extension's group/kind (any ancestor, not just direct parent).
- **Combined matching:** Extension activates when EITHER (a) the resource matches group/kind directly, OR (b) the resource has an ancestor matching group/kind.
- **Backwards compatibility:** Existing extensions (no new opts) behave exactly as today.
- **Opt-in:** New behavior is opt-in via `matchOnAncestors: true` in opts.

## API Changes

### 1. `registerResourceExtension`

Extend the optional `opts` parameter:

```typescript
registerResourceExtension(
  component: ExtensionComponent,
  group: string,
  kind: string,
  tabTitle: string,
  opts?: { icon?: string; matchOnAncestors?: boolean }
)
```

### 2. `ResourceTabExtension` interface

```typescript
export interface ResourceTabExtension {
  title: string;
  group: string;
  kind: string;
  component: ExtensionComponent;
  icon?: string;
  matchOnAncestors?: boolean;
}
```

### 3. `getResourceTabs` signature

```typescript
getResourceTabs(
  group: string,
  kind: string,
  tree?: ApplicationTree,
  selectedNode?: ResourceNode
): ResourceTabExtension[]
```

When `tree` and `selectedNode` are omitted, only direct matching applies (backwards compatible).

## Matching Logic

For each extension:

1. **Direct match:** `minimatch(selectedNode.group, ext.group) && minimatch(selectedNode.kind, ext.kind)` — unchanged.
2. **Ancestor match:** When `ext.matchOnAncestors === true` and `tree` and `selectedNode` are provided, traverse ancestors via `parentRefs`, resolving each parent from `tree.nodes` and `tree.orphanedNodes`. Extension matches if any ancestor matches `ext.group` and `ext.kind`.

Helper: `hasAncestorMatching(node, tree, group, kind)` — walks parent chain, uses `nodeKey()` for lookups, includes orphaned nodes.

## Data Flow

| Call site | Change |
|-----------|--------|
| `resource-details.tsx` (resource panel) | Add `tree, selectedNode` to `getResourceTabs` |
| `resource-details.tsx` (Application tabs) | No change |
| `appset-resource-details.tsx` | No change |

## Edge Cases

| Case | Handling |
|------|----------|
| No `parentRefs` | Ancestor match fails; direct match only |
| Parent not found in tree | Skip; continue with others |
| Circular refs | Track visited keys; stop if seen twice |
| `tree` or `selectedNode` null | Skip ancestor matching |
| Orphaned nodes | Include `orphanedNodes` when resolving parents |

## Error Handling

- Ancestor traversal is synchronous; no async or external calls.
- If traversal throws, catch in `getResourceTabs` and fall back to direct match only.
- Extensions unchanged; no new error paths in extension code.

## Testing

- Unit tests for `getResourceTabs` / ancestor helper: direct match, ancestor match, both, missing parent, circular refs, omitted tree/node.
- Integration: manual verification with Rollout-style extension.
- Docs: update `docs/developer-guide/extensions/ui-extensions.md` with `matchOnAncestors` and example.
