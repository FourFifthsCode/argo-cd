import * as minimatch from 'minimatch';

import {ApplicationTree, ResourceNode} from '../models';

export function nodeKey(ref: {group: string; kind: string; namespace: string; name: string}): string {
    return [ref.group, ref.kind, ref.namespace, ref.name].join('/');
}

/**
 * Returns true if any ancestor of the given node matches the specified group and kind.
 * Walks parentRefs recursively, resolving parents from tree.nodes and tree.orphanedNodes.
 * Tracks visited keys to avoid circular refs. Skips missing parents.
 */
export function hasAncestorMatching(
    node: ResourceNode,
    tree: ApplicationTree,
    group: string,
    kind: string
): boolean {
    const allNodes = [...(tree.nodes || []), ...(tree.orphanedNodes || [])];
    const nodeByKey = new Map<string, ResourceNode>();
    allNodes.forEach(n => nodeByKey.set(nodeKey(n), n));

    const visited = new Set<string>();
    const queue: ResourceNode[] = [node];

    while (queue.length > 0) {
        const current = queue.shift()!;
        const currentKey = nodeKey(current);

        if (visited.has(currentKey)) {
            continue;
        }
        visited.add(currentKey);

        for (const parentRef of current.parentRefs || []) {
            const parentKey = nodeKey(parentRef);
            if (visited.has(parentKey)) {
                continue;
            }

            const parent = nodeByKey.get(parentKey);
            if (!parent) {
                continue;
            }

            if (minimatch(parent.group, group) && minimatch(parent.kind, kind)) {
                return true;
            }

            queue.push(parent);
        }
    }

    return false;
}
