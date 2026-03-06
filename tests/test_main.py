import importlib.util
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "src" / "main.py"
SPEC = importlib.util.spec_from_file_location("karb_main", MODULE_PATH)
MAIN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAIN)


class StoppedState:
    def __init__(self, stopped: bool):
        self._stopped = stopped

    def __bool__(self):
        return self._stopped

    def wait(self, _seconds: int):
        return None


def test_get_exec_command_defaults_to_sh_c():
    command = MAIN.get_exec_command(None, "echo hello")
    assert command == ["/bin/sh", "-c", "echo hello"]


def test_get_main_container_by_annotation_name():
    spec = {
        "containers": [
            {"name": "sidecar"},
            {"name": "app"},
        ]
    }

    container = MAIN.get_main_container(spec, "app")
    assert container["name"] == "app"


def test_get_api_raises_temporary_error_if_not_initialized():
    previous_api = MAIN.api
    MAIN.api = None
    try:
        with pytest.raises(MAIN.kopf.TemporaryError):
            MAIN.get_api()
    finally:
        MAIN.api = previous_api


def test_configure_initializes_api_and_webhook_settings():
    settings = SimpleNamespace(
        posting=SimpleNamespace(level=None),
        execution=SimpleNamespace(max_workers=None),
        admission=SimpleNamespace(server=None),
    )

    with patch.object(MAIN, "initialize_kubernetes_api", return_value=object()):
        MAIN.configure(settings)

    assert settings.posting.level == MAIN.logging.INFO
    assert settings.execution.max_workers == 1000
    assert settings.admission.server is not None


def test_run_backups_rejects_non_integer_schedule():
    with pytest.raises(MAIN.kopf.PermanentError, match="must be an integer"):
        MAIN.run_backups(
            stopped=StoppedState(True),
            name="pod-1",
            namespace="default",
            spec={"containers": [{"name": "app"}]},
            annotations={"karb.boa.nu/backup-schedule": "abc"},
        )


def test_run_backups_rejects_non_positive_schedule():
    with pytest.raises(MAIN.kopf.PermanentError, match="between 1 and 86400"):
        MAIN.run_backups(
            stopped=StoppedState(True),
            name="pod-1",
            namespace="default",
            spec={"containers": [{"name": "app"}]},
            annotations={"karb.boa.nu/backup-schedule": "0"},
        )


def test_mutate_rejects_invalid_backup_name():
    body = {
        "spec": {
            "containers": [{"name": "app"}],
            "volumes": [],
            "initContainers": [],
        }
    }
    annotations = {
        "karb.boa.nu/backup-schedule": "30",
        "karb.boa.nu/backup-name": "../../etc/passwd",
        "karb.boa.nu/restore-exec": "echo restore",
    }
    patch_obj = SimpleNamespace(spec={})

    with pytest.raises(MAIN.kopf.PermanentError, match="backup-name"):
        MAIN.mutate(body=body, annotations=annotations, patch=patch_obj)


def test_mutate_adds_volume_mount_when_volume_mounts_missing():
    body = {
        "spec": {
            "containers": [{"name": "app"}],
            "volumes": [],
            "initContainers": [],
        }
    }
    annotations = {
        "karb.boa.nu/backup-schedule": "30",
        "karb.boa.nu/backup-name": "default",
        "karb.boa.nu/restore-exec": "echo restore",
    }
    patch_obj = SimpleNamespace(spec={})

    with patch.dict(
        MAIN.os.environ,
        {"NFS_SERVER": "nfs.example", "NFS_ROOT_PATH": "/exports/karb"},
        clear=False,
    ):
        with patch.object(MAIN.os, "makedirs", return_value=None):
            MAIN.mutate(body=body, annotations=annotations, patch=patch_obj)

    volume_names = [v["name"] for v in patch_obj.spec["volumes"]]
    assert "karb-backup-volume" in volume_names

    app_container = patch_obj.spec["containers"][0]
    mount_names = [v["name"] for v in app_container["volumeMounts"]]
    assert "karb-backup-volume" in mount_names

    init_names = [c["name"] for c in patch_obj.spec["initContainers"]]
    assert "karb-restorer" in init_names


def test_mutate_supports_hostpath_backend():
    body = {
        "spec": {
            "containers": [{"name": "app"}],
            "volumes": [],
            "initContainers": [],
        }
    }
    annotations = {
        "karb.boa.nu/backup-schedule": "30",
        "karb.boa.nu/backup-name": "hostpath-e2e",
        "karb.boa.nu/restore-exec": "echo restore",
    }
    patch_obj = SimpleNamespace(spec={})

    with patch.dict(
        MAIN.os.environ,
        {
            "KARB_VOLUME_BACKEND": "hostPath",
            "KARB_HOSTPATH_ROOT": "/var/lib/karb-e2e",
            "KARB_ALLOW_HOSTPATH_BACKEND": "true",
        },
        clear=False,
    ):
        MAIN.mutate(body=body, annotations=annotations, patch=patch_obj)

    volume = next(
        v for v in patch_obj.spec["volumes"] if v["name"] == "karb-backup-volume"
    )
    assert volume["hostPath"]["path"] == "/var/lib/karb-e2e/hostpath-e2e"
    assert volume["hostPath"]["type"] == "DirectoryOrCreate"


def test_mutate_rejects_hostpath_backend_when_not_allowed():
    body = {
        "spec": {
            "containers": [{"name": "app"}],
            "volumes": [],
            "initContainers": [],
        }
    }
    annotations = {
        "karb.boa.nu/backup-schedule": "30",
        "karb.boa.nu/backup-name": "hostpath-e2e",
        "karb.boa.nu/restore-exec": "echo restore",
    }
    patch_obj = SimpleNamespace(spec={})

    with patch.dict(
        MAIN.os.environ,
        {
            "KARB_VOLUME_BACKEND": "hostPath",
            "KARB_HOSTPATH_ROOT": "/var/lib/karb-e2e",
            "KARB_ALLOW_HOSTPATH_BACKEND": "false",
        },
        clear=False,
    ):
        with pytest.raises(
            MAIN.kopf.PermanentError, match="hostPath backend is disabled"
        ):
            MAIN.mutate(body=body, annotations=annotations, patch=patch_obj)
