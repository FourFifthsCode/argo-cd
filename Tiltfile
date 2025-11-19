load('ext://restart_process', 'docker_build_with_restart')
load('ext://uibutton', 'cmd_button', 'location')

# add ui button in web ui to run make codegen-local (top nav)
cmd_button(
    'make codegen-local',
    argv=['sh', '-c', 'make codegen-local'],
    location=location.NAV,
    icon_name='terminal',
    text='make codegen-local',
)

cmd_button(
    'make test-local',
    argv=['sh', '-c', 'make test-local'],
    location=location.NAV,
    icon_name='science',
    text='make test-local',
)

# add ui button in web ui to run make codegen-local (top nav)
cmd_button(
    'make cli-local',
    argv=['sh', '-c', 'make cli-local'],
    location=location.NAV,
    icon_name='terminal',
    text='make cli-local',
)

# detect cluster architecture for build
cluster_version = decode_yaml(local('kubectl version -o yaml'))
platform = cluster_version['serverVersion']['platform']
arch = platform.split('/')[1]

# build the argocd binary on code changes
code_deps = [
    'applicationset',
    'cmd',
    'cmpserver',
    'commitserver',
    'common',
    'controller',
    'notification-controller',
    'pkg',
    'reposerver',
    'server',
    'util',
    'go.mod',
    'go.sum',
]
# dev setup - ensures DNS, TLS, CoreDNS, and ArgoCD CA are configured
# MUST run before kustomize builds (which need the certs)
local_resource(
    'dev-setup',
    'hack/dev-minikube-setup.sh setup',
    auto_init=True,
    allow_parallel=True,
    labels=['setup']
)

local_resource(
    'build',
    'CGO_ENABLED=0 GOOS=linux GOARCH=' + arch + ' go build -gcflags="all=-N -l" -mod=readonly -o .tilt-bin/argocd_linux cmd/main.go',
    deps = code_deps,
    allow_parallel=True,
    labels=['argocd']
)

# deploy the argocd manifests - depends on dev-setup to ensure certs exist
local_resource(
    'kustomize-build',
    'kustomize build manifests/dev-tilt > .tilt/argocd.yaml && kustomize build manifests/dev-tilt/keycloak > .tilt/keycloak.yaml',
    deps=['manifests/dev-tilt', 'manifests/dev-tilt/keycloak'],
    resource_deps=['dev-setup'],
    auto_init=True,
    allow_parallel=True,
    labels=['setup']
)

k8s_yaml('.tilt/argocd.yaml')
k8s_yaml('.tilt/keycloak.yaml')

# build dev image
docker_build_with_restart(
    'argocd', 
    context='.',
    dockerfile='Dockerfile.tilt',
    entrypoint=[
        "/usr/bin/tini",
        "-s",
        "--",
        "dlv",
        "exec",
        "--continue",
        "--accept-multiclient",
        "--headless",
        "--listen=:2345",
        "--api-version=2"
    ],
    platform=platform,
    live_update=[
        sync('.tilt-bin/argocd_linux', '/usr/local/bin/argocd'),
    ],
    only=[
        '.tilt-bin',
        'hack',
        'entrypoint.sh',
    ],
    restart_file='/tilt/.restart-proc'
)

# build image for argocd-cli jobs
docker_build(
    'argocd-job', 
    context='.',
    dockerfile='Dockerfile.tilt',
    platform=platform,
    only=[
        '.tilt-bin',
        'hack',
        'entrypoint.sh',
    ]
)

# track argocd-server resources and port forward
k8s_resource(
    workload='argocd-server',
    objects=[
        'argocd-server:serviceaccount',
        'argocd-server:role',
        'argocd-server:rolebinding',
        'argocd-cm:configmap',
        'argocd-cmd-params-cm:configmap',
        'argocd-gpg-keys-cm:configmap',
        'argocd-rbac-cm:configmap',
        'argocd-ssh-known-hosts-cm:configmap',
        'argocd-tls-certs-cm:configmap',
        'argocd-secret:secret',
        'argocd-server-network-policy:networkpolicy',
        'argocd-server:clusterrolebinding',
        'argocd-server:clusterrole',
    ],
    port_forwards=[
        '8080:8080',
        '9345:2345',
        '8083:8083'
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track crds
k8s_resource(
    new_name='cluster-resources',
    objects=[
        'applications.argoproj.io:customresourcedefinition',
        'applicationsets.argoproj.io:customresourcedefinition',
        'appprojects.argoproj.io:customresourcedefinition',
        'argocd:namespace'
    ],
    labels=['argocd']
)

# track argocd-repo-server resources and port forward
k8s_resource(
    workload='argocd-repo-server',
    objects=[
        'argocd-repo-server:serviceaccount',
        'argocd-repo-server-network-policy:networkpolicy',
    ],
    port_forwards=[
        '8081:8081',
        '9346:2345',
        '8084:8084'
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-redis resources and port forward
k8s_resource(
    workload='argocd-redis',
    objects=[
        'argocd-redis:serviceaccount',
        'argocd-redis:role',
        'argocd-redis:rolebinding',
        'argocd-redis-network-policy:networkpolicy',
    ],
    port_forwards=[
        '6379:6379',
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-applicationset-controller resources
k8s_resource(
    workload='argocd-applicationset-controller',
    objects=[
        'argocd-applicationset-controller:serviceaccount',
        'argocd-applicationset-controller-network-policy:networkpolicy',
        'argocd-applicationset-controller:role',
        'argocd-applicationset-controller:rolebinding',
        'argocd-applicationset-controller:clusterrolebinding',
        'argocd-applicationset-controller:clusterrole',
    ],
    port_forwards=[
        '9347:2345',
        '8085:8080',
        '7000:7000'
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-application-controller resources
k8s_resource(
    workload='argocd-application-controller',
    objects=[
        'argocd-application-controller:serviceaccount',
        'argocd-application-controller-network-policy:networkpolicy',
        'argocd-application-controller:role',
        'argocd-application-controller:rolebinding',
        'argocd-application-controller:clusterrolebinding',
        'argocd-application-controller:clusterrole',
    ],
    port_forwards=[
        '9348:2345',
        '8086:8082',
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-notifications-controller resources
k8s_resource(
    workload='argocd-notifications-controller',
    objects=[
        'argocd-notifications-controller:serviceaccount',
        'argocd-notifications-controller-network-policy:networkpolicy',
        'argocd-notifications-controller:role',
        'argocd-notifications-controller:rolebinding',
        'argocd-notifications-cm:configmap',
        'argocd-notifications-secret:secret',
    ],
    port_forwards=[
        '9349:2345',
        '8087:9001',
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-dex-server resources
k8s_resource(
    workload='argocd-dex-server',
    objects=[
        'argocd-dex-server:serviceaccount',
        'argocd-dex-server-network-policy:networkpolicy',
        'argocd-dex-server:role',
        'argocd-dex-server:rolebinding',
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# track argocd-commit-server resources
k8s_resource(
    workload='argocd-commit-server',
    objects=[
        'argocd-commit-server:serviceaccount',
        'argocd-commit-server-network-policy:networkpolicy',
    ],
    port_forwards=[
        '9350:2345',
        '8088:8087',
        '8089:8086',
    ],
    resource_deps=['build'],
    labels=['argocd']
)

# ui dependencies
local_resource(
    'node-modules',
    'yarn',
    dir='ui',
    deps = [
        'ui/package.json',
        'ui/yarn.lock',
    ],
    allow_parallel=True,
    labels=['argocd']
)

# docker for ui
docker_build(
    'argocd-ui',
    context='.',
    dockerfile='Dockerfile.ui.tilt',
    entrypoint=['sh', '-c', 'cd /app/ui && yarn start'], 
    only=['ui'],
    live_update=[
        sync('ui', '/app/ui'),
        run('sh -c "cd /app/ui && yarn install"', trigger=['/app/ui/package.json', '/app/ui/yarn.lock']),
    ]
)

# track argocd-ui resources and port forward
k8s_resource(
    workload='argocd-ui',
    objects=[
        'keycloak-tls:secret:argocd',
        'argocd-ui:ingress:argocd',
    ],
    port_forwards=[
        '4000:4000',
    ],
    resource_deps=['node-modules'],
    labels=['argocd']
)

# linting
local_resource(
    'lint',
    'make lint-local',
    deps = code_deps,
    allow_parallel=True,
    resource_deps=['vendor'],
    labels=['tools']
)

local_resource(
    'lint-ui',
    'make lint-ui-local',
    deps = [
        'ui',
    ],
    allow_parallel=True,
    resource_deps=['node-modules'],
    labels=['tools']
)

local_resource(
    'vendor',
    'go mod vendor',
    deps = [
        'go.mod',
        'go.sum',
    ],
    allow_parallel=True,
    labels=['tools']
)

local_resource(
    'minkube-tunnel',
    serve_cmd='minikube tunnel',
    allow_parallel=True,
    labels=['setup']
)

k8s_resource(
    workload='keycloak',
    objects=[
        'keycloak-tls:secret:keycloak',
        'keycloak-realm-config:configmap:keycloak',
        'keycloak:ingress:keycloak',
        'oidc-config:secret:argocd'
    ],
    port_forwards=[
        '8180:8080',
    ],
    resource_deps=[
        'postgres',
    ],
    labels=['keycloak'],
)

k8s_resource(
    workload='postgres',
    labels=['keycloak'],
    objects=[
        'keycloak:namespace',
    ],
)