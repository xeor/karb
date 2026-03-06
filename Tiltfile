allow_k8s_contexts('kind-karb-e2e')

local_resource(
    'bootstrap-kind',
    './hack/kind-e2e/bootstrap.sh',
    auto_init=True,
    trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
    'build-image',
    './hack/kind-e2e/build-and-load.sh ghcr.io/xeor/karb:e2e-local',
    deps=[
        'Containerfile',
        'pyproject.toml',
        'uv.lock',
        'src',
    ],
    resource_deps=['bootstrap-kind'],
    auto_init=True,
    trigger_mode=TRIGGER_MODE_AUTO,
)

k8s_yaml(helm(
    './charts/karb',
    name='karb',
    namespace='karb-system',
    values=['./hack/kind-e2e/values/karb-kind-values.yaml'],
))

k8s_resource('karb', resource_deps=['bootstrap-kind', 'build-image'])

local_resource(
    'kind-down',
    './hack/kind-e2e/down.sh',
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
)

local_resource(
    'unit-tests',
    'uv run pytest -q',
    deps=['src', 'tests', 'pyproject.toml', 'uv.lock'],
    trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
    'py-compile',
    'uv run python -m py_compile src/main.py',
    deps=['src/main.py'],
    trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
    'e2e-test',
    './hack/kind-e2e/test.sh',
    deps=[
        'hack/kind-e2e/manifests/test-pod.yaml',
        'hack/kind-e2e/values/karb-kind-values.yaml',
        'charts/karb',
        'src',
    ],
    resource_deps=['karb'],
    trigger_mode=TRIGGER_MODE_MANUAL,
)
