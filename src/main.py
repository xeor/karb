import os
import time
import logging
import re
from typing import Optional

import kopf

from kubernetes import config, client
from kubernetes.stream import stream

import prometheus_client as prometheus

BACKUP_SCHEDULE_ANNOTATION = "karb.boa.nu/backup-schedule"
BACKUP_NAME_ANNOTATION = "karb.boa.nu/backup-name"
CONTAINER_NAME_ANNOTATION = "karb.boa.nu/container-name"
BACKUP_EXEC_ANNOTATION = "karb.boa.nu/backup-exec"
BACKUP_EXEC_SHELL_ANNOTATION = "karb.boa.nu/backup-exec-shell"
RESTORE_EXEC_ANNOTATION = "karb.boa.nu/restore-exec"
RESTORE_EXEC_SHELL_ANNOTATION = "karb.boa.nu/restore-exec-shell"

BACKUP_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
ALLOWED_EXEC_SHELLS = {"/bin/sh -c", "/bin/bash -c"}
MIN_BACKUP_SCHEDULE_SECONDS = 1
MAX_BACKUP_SCHEDULE_SECONDS = 86400

if hasattr(prometheus, "disable_created_metrics"):
    prometheus.disable_created_metrics()

prometheus.start_http_server(9090)
m_exec_summary = prometheus.Summary(
    "karb_exec_seconds",
    "Time spent executing successful backup command",
    [
        "friendly_name",
        "namespace",
        "pod_name",
        "container_name",
        "backup_name",
        "backup_schedule",
    ],
)
m_exec_counter = prometheus.Counter(
    "karb_exec_total",
    "Total exec requests",
    [
        "friendly_name",
        "status",
        "namespace",
        "pod_name",
        "container_name",
        "backup_name",
        "backup_schedule",
    ],
)

api: Optional[client.CoreV1Api] = None


def initialize_kubernetes_api() -> client.CoreV1Api:
    if "DEV" in os.environ:
        config.load_kube_config()
    else:
        config.load_incluster_config()
    return client.CoreV1Api()


def get_api() -> client.CoreV1Api:
    if api is None:
        raise kopf.TemporaryError("Kubernetes API client is not initialized", delay=10)
    return api


def is_pod_ready(namespace, pod_name):
    api_client = get_api()
    try:
        pod = api_client.read_namespaced_pod(namespace=namespace, name=pod_name)
        if pod.status.conditions:
            for condition in pod.status.conditions:
                if condition.type == "Ready" and condition.status == "True":
                    return True
        return False
    except client.rest.ApiException as err:
        logging.warning("API exception when reading pod status: %s", err)
        return False


def validate_backup_name(backup_name: str) -> str:
    if not BACKUP_NAME_PATTERN.fullmatch(backup_name):
        raise kopf.PermanentError(
            "backup-name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
        )
    return backup_name


def parse_backup_schedule(schedule_raw: str) -> int:
    try:
        schedule = int(schedule_raw)
    except ValueError as err:
        raise kopf.PermanentError("backup-schedule must be an integer") from err

    if schedule < MIN_BACKUP_SCHEDULE_SECONDS or schedule > MAX_BACKUP_SCHEDULE_SECONDS:
        raise kopf.PermanentError("backup-schedule must be between 1 and 86400 seconds")
    return schedule


def validate_command(command: Optional[str], annotation_name: str) -> str:
    if not command or not command.strip():
        raise kopf.PermanentError(f"{annotation_name} must be a non-empty string")
    return command


def validate_shell(shell: Optional[str], annotation_name: str) -> Optional[str]:
    if shell is None:
        return None
    if shell not in ALLOWED_EXEC_SHELLS:
        allowed_shells = ", ".join(sorted(ALLOWED_EXEC_SHELLS))
        raise kopf.PermanentError(f"{annotation_name} must be one of: {allowed_shells}")
    return shell


def get_exec_command(shell, command):
    command = validate_command(command, "command")
    shell = validate_shell(shell, "shell")

    if shell:
        shell = shell.split()
    else:
        shell = ["/bin/sh", "-c"]

    return shell + [command]


def exec_backup_command_in_pod(
    namespace,
    pod_name,
    container_name,
    command,
    shell=None,
    backup_name="",
    backup_schedule="",
):
    if not command:
        raise kopf.TemporaryError(f"No command specified", delay=60)

    exec_command = get_exec_command(shell, command)

    # logging.info(f"exec: {namespace=}, {pod_name=}, {container_name=}, {exec_command=}")

    friendly_name = f"{namespace}/{pod_name} ({backup_name})"

    start_time = time.time()
    try:
        resp = stream(
            get_api().connect_get_namespaced_pod_exec,
            pod_name,
            namespace,
            command=exec_command,
            container=container_name,
            stderr=True,
            stdin=False,
            stdout=True,
            tty=False,
        )
    except Exception as err:
        m_exec_counter.labels(
            friendly_name,
            "failed",
            namespace,
            pod_name,
            container_name,
            backup_name,
            backup_schedule,
        ).inc()
        raise kopf.TemporaryError(f"Error during exec: {err}", delay=60)

    # Check if we can get returncode of the command as well
    duration = time.time() - start_time
    m_exec_summary.labels(
        friendly_name, namespace, pod_name, container_name, backup_name, backup_schedule
    ).observe(duration)

    m_exec_counter.labels(
        friendly_name,
        "success",
        namespace,
        pod_name,
        container_name,
        backup_name,
        backup_schedule,
    ).inc()
    return resp


def get_main_container(spec, name):
    if len(spec["containers"]) == 1:
        return spec["containers"][0]

    for i in spec["containers"]:
        if i["name"] == name:
            return i

    raise kopf.TemporaryError(f"No container named {name} found.", delay=60)


@kopf.on.login()
def login(**kwargs):
    token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
    if os.path.isfile(token_file):
        logging.info(
            f"Found serviceaccount token file at {token_file}. Login via service-account"
        )
        return kopf.login_with_service_account(**kwargs)
    logging.info("Login via kubeconfig, no token-file found")
    return kopf.login_with_kubeconfig(**kwargs)


@kopf.on.startup()
def configure(settings: kopf.OperatorSettings, **_):
    global api
    api = initialize_kubernetes_api()

    settings.posting.level = logging.INFO
    settings.execution.max_workers = 1000

    webhook_config = {
        "port": int(os.environ.get("webhook_port", "8443")),
        "addr": "0.0.0.0",
        "cafile": "/etc/certs/ca.crt",
        "certfile": "/etc/certs/tls.crt",
        "pkeyfile": "/etc/certs/tls.key",
    }
    if "webhook_host" in os.environ:
        webhook_config["host"] = os.environ["webhook_host"]
    settings.admission.server = kopf.WebhookServer(**webhook_config)


@kopf.daemon("pods.v1", annotations={BACKUP_SCHEDULE_ANNOTATION: kopf.PRESENT})
def run_backups(stopped, name, namespace, spec, annotations, **kwargs):
    while not stopped and not is_pod_ready(namespace, name):
        logging.info(f"Pod in {namespace}/{name} not ready yet...")
        stopped.wait(5)

    schedule = parse_backup_schedule(annotations[BACKUP_SCHEDULE_ANNOTATION])
    backup_name = validate_backup_name(
        annotations.get(BACKUP_NAME_ANNOTATION, "default")
    )
    backup_shell = validate_shell(
        annotations.get(BACKUP_EXEC_SHELL_ANNOTATION), BACKUP_EXEC_SHELL_ANNOTATION
    )
    backup_command = validate_command(
        annotations.get(BACKUP_EXEC_ANNOTATION), BACKUP_EXEC_ANNOTATION
    )

    logging.info(
        f"Pod in {namespace}/{name} ready. Will backup every {schedule} seconds"
    )

    container = get_main_container(
        spec, name=annotations.get(CONTAINER_NAME_ANNOTATION)
    )
    while not stopped:
        ret = exec_backup_command_in_pod(
            namespace,
            name,
            container["name"],
            backup_command,
            shell=backup_shell,
            backup_name=backup_name,
            backup_schedule=str(schedule),
        )
        logging.info(
            f"Executed backup-exec-shell command in {namespace}/{name} [{container['name']}] with return {ret}"
        )

        stopped.wait(schedule)


@kopf.on.mutate("pods.v1", annotations={BACKUP_SCHEDULE_ANNOTATION: kopf.PRESENT})
def mutate(body, annotations, patch, **kwargs):
    spec = body["spec"]
    containers = spec.get("containers", [])
    init_containers = spec.get("initContainers", [])
    volumes = spec.get("volumes", [])

    parse_backup_schedule(annotations[BACKUP_SCHEDULE_ANNOTATION])
    backupname = validate_backup_name(
        annotations.get(BACKUP_NAME_ANNOTATION, "default")
    )
    restore_shell = validate_shell(
        annotations.get(RESTORE_EXEC_SHELL_ANNOTATION), RESTORE_EXEC_SHELL_ANNOTATION
    )
    restore_command = validate_command(
        annotations.get(RESTORE_EXEC_ANNOTATION), RESTORE_EXEC_ANNOTATION
    )

    if "karb-backup-volume" not in [i["name"] for i in volumes]:
        volume_backend = os.environ.get("KARB_VOLUME_BACKEND", "nfs")

        if volume_backend == "hostPath":
            hostpath_allowed = os.environ.get(
                "KARB_ALLOW_HOSTPATH_BACKEND", "false"
            ).lower() in {"1", "true", "yes"}
            if not hostpath_allowed:
                raise kopf.PermanentError(
                    "hostPath backend is disabled. Set KARB_ALLOW_HOSTPATH_BACKEND=true to enable it"
                )
            hostpath_root = os.environ.get("KARB_HOSTPATH_ROOT", "/var/lib/karb")
            volumes.append(
                {
                    "name": "karb-backup-volume",
                    "hostPath": {
                        "path": f"{hostpath_root}/{backupname}",
                        "type": "DirectoryOrCreate",
                    },
                }
            )
        else:
            nfs_root_path = os.environ["NFS_ROOT_PATH"]
            os.makedirs(f"/karb-data-root/{backupname}", exist_ok=True)
            volumes.append(
                {
                    "name": "karb-backup-volume",
                    "nfs": {
                        "server": os.environ["NFS_SERVER"],
                        "path": f"{nfs_root_path}/{backupname}",
                    },
                }
            )
        patch.spec["volumes"] = volumes

    container = get_main_container(
        spec, name=annotations.get(CONTAINER_NAME_ANNOTATION)
    )

    volume_mounts = container.setdefault("volumeMounts", [])
    if "karb-backup-volume" not in [i["name"] for i in volume_mounts]:
        volume_mounts.append(
            {
                "name": "karb-backup-volume",
                "readOnly": False,
                "mountPath": "/karb-data",
            }
        )
    patch.spec["containers"] = containers

    if "karb-restorer" not in [i["name"] for i in init_containers]:
        init_container = container.copy()
        init_container["name"] = "karb-restorer"
        init_container["command"] = get_exec_command(restore_shell, restore_command)

        init_containers.append(init_container)
        patch.spec["initContainers"] = init_containers

    return {}
