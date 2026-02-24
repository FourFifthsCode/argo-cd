import {ApplicationTree, ResourceNode} from '../models';
import {hasAncestorMatching, nodeKey} from './extensions-service-helpers';

function makeNode(
    group: string,
    kind: string,
    namespace: string,
    name: string,
    parentRefs: Array<{group: string; kind: string; namespace: string; name: string}> = []
): ResourceNode {
    return {
        group,
        kind,
        namespace,
        name,
        uid: `${group}/${kind}/${namespace}/${name}`,
        version: 'v1',
        resourceVersion: '1',
        parentRefs: parentRefs.map(p => ({
            ...p,
            uid: `${p.group}/${p.kind}/${p.namespace}/${p.name}`,
            version: 'v1'
        })),
        info: []
    };
}

test('nodeKey returns correct format', () => {
    expect(nodeKey({group: 'apps', kind: 'Deployment', namespace: 'default', name: 'foo'})).toBe(
        'apps/Deployment/default/foo'
    );
});

test('hasAncestorMatching returns true when direct parent matches', () => {
    const rollout = makeNode('argoproj.io', 'Rollout', 'default', 'my-rollout');
    const rs = makeNode('apps', 'ReplicaSet', 'default', 'my-rs', [
        {group: 'argoproj.io', kind: 'Rollout', namespace: 'default', name: 'my-rollout'}
    ]);
    const tree: ApplicationTree = {
        nodes: [rollout, rs],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(rs, tree, 'argoproj.io', 'Rollout')).toBe(true);
});

test('hasAncestorMatching returns true when ancestor two levels up matches', () => {
    const rollout = makeNode('argoproj.io', 'Rollout', 'default', 'my-rollout');
    const rs = makeNode('apps', 'ReplicaSet', 'default', 'my-rs', [
        {group: 'argoproj.io', kind: 'Rollout', namespace: 'default', name: 'my-rollout'}
    ]);
    const pod = makeNode('', 'Pod', 'default', 'my-pod', [
        {group: 'apps', kind: 'ReplicaSet', namespace: 'default', name: 'my-rs'}
    ]);
    const tree: ApplicationTree = {
        nodes: [rollout, rs, pod],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(pod, tree, 'argoproj.io', 'Rollout')).toBe(true);
});

test('hasAncestorMatching returns false when no ancestor matches', () => {
    const rs = makeNode('apps', 'ReplicaSet', 'default', 'my-rs', [
        {group: 'apps', kind: 'Deployment', namespace: 'default', name: 'my-deploy'}
    ]);
    const tree: ApplicationTree = {
        nodes: [rs],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(rs, tree, 'argoproj.io', 'Rollout')).toBe(false);
});

test('hasAncestorMatching returns false when node has no parentRefs', () => {
    const rollout = makeNode('argoproj.io', 'Rollout', 'default', 'my-rollout');
    const tree: ApplicationTree = {
        nodes: [rollout],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(rollout, tree, 'argoproj.io', 'Rollout')).toBe(false);
});

test('hasAncestorMatching handles missing parent in tree', () => {
    const rs = makeNode('apps', 'ReplicaSet', 'default', 'my-rs', [
        {group: 'argoproj.io', kind: 'Rollout', namespace: 'default', name: 'nonexistent-rollout'}
    ]);
    const tree: ApplicationTree = {
        nodes: [rs],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(rs, tree, 'argoproj.io', 'Rollout')).toBe(false);
});

test('hasAncestorMatching handles circular parentRefs', () => {
    const nodeA = makeNode('apps', 'A', 'default', 'a', [
        {group: 'apps', kind: 'B', namespace: 'default', name: 'b'}
    ]);
    const nodeB = makeNode('apps', 'B', 'default', 'b', [
        {group: 'apps', kind: 'A', namespace: 'default', name: 'a'}
    ]);
    const tree: ApplicationTree = {
        nodes: [nodeA, nodeB],
        orphanedNodes: []
    };

    expect(hasAncestorMatching(nodeA, tree, 'argoproj.io', 'Rollout')).toBe(false);
});

test('hasAncestorMatching includes orphanedNodes when building nodeByKey', () => {
    const orphanedRollout = makeNode('argoproj.io', 'Rollout', 'default', 'orphaned-rollout');
    const rs = makeNode('apps', 'ReplicaSet', 'default', 'my-rs', [
        {group: 'argoproj.io', kind: 'Rollout', namespace: 'default', name: 'orphaned-rollout'}
    ]);
    const tree: ApplicationTree = {
        nodes: [rs],
        orphanedNodes: [orphanedRollout]
    };

    expect(hasAncestorMatching(rs, tree, 'argoproj.io', 'Rollout')).toBe(true);
});
