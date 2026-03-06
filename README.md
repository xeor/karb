# karb - k8s App-controlled Restore & Backup

## Intro

There are many backup solutions for Kubernetes, but many of them are overly complicated.
`karb` solves backup/restore in another way: let the application backup and restore itself
using small scripts in pod annotations.

This is best suited for smaller clusters and home labs where app-managed backup/restore is desired.

Why use this:

- You want the application itself to produce its backup format.
- You do not want restore to depend on external object storage.
- You want a simple reinstall/restore flow from persisted backup files.

Why not use this:

- You need a battle-tested full-cluster backup platform.
- You need to backup full Kubernetes context/state, not just app data.

## How it works

`karb` is an operator that watches pods with specific annotations.

- Injects backup volume into app container on `/karb-data`.
- Executes annotation-defined backup command on a schedule.
- Injects restore init-container (`karb-restorer`) on pod creation.
- Mount path is selected by `backup-name` (stable path by design).

This allows automatic restore after reinstallation as long as backup storage persists.

## Security

The application container has access to its backup volume; treat app compromise as backup compromise.
Do not rely on `karb` as the only backup layer.

Security defaults include:

- minimal RBAC for watch/patch/exec/events
- container hardening (`allowPrivilegeEscalation: false`, `runAsNonRoot: true`, dropped capabilities)
- annotation input validation (`backup-name`, schedule, shell, command)

## Installation and configuration

Prerequisites:

- Kubernetes cluster
- cert-manager
- backup backend (NFS for production)

Install:

```bash
helm upgrade --install karb ./charts/karb --namespace karb-system --create-namespace -f values.yaml
```

## Development testing

Use docs in `docs/`:

- `docs/README.md`
- `docs/development.md`
- `docs/release-readiness.md`

Run tests:

```bash
task test
```

## Spec

Heavily commented example pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example
  annotations:

    # Will be the subfolder of your backup volume. If you have configured
    # the operator to use path `/data/backup`, it will become `/data/backup/test`
    # in this case. Default is "default" if this annotation is left out.
    karb.boa.nu/backup-name: "test"

    # What container to run backup commands in and base the init container on.
    # It is important that this is the app container itself. If left out
    # and there is only one container, we will use that. If there are more than one
    # and this is not defined, you will get an error.
    karb.boa.nu/container-name: "my-container"

    # How many seconds between each backup. Valid range is 1..86400.
    karb.boa.nu/backup-schedule: "100"

    # Shell for backup command/script.
    # Supported values: "/bin/sh -c", "/bin/bash -c"
    karb.boa.nu/backup-exec-shell: "/bin/sh -c"

    # Script or command for backup. Runs inside the app container.
    # Put backup artifacts in /karb-data.
    karb.boa.nu/backup-exec: |
      date >> /karb-data/test

    # Same concept as karb.boa.nu/backup-exec-shell.
    karb.boa.nu/restore-exec-shell: "/bin/sh -c"

    # Restore command in init container during pod startup.
    # Validate restore conditions before writing data.
    karb.boa.nu/restore-exec: |
      if [ -f "/karb-data/test" ]; then
        cp /karb-data/test /etc/test
        echo restored
        exit 0
      fi
      echo "not restoring"

spec:
  containers:
    - name: my-container
      image: busybox
      command: ["sh", "-c", "echo 'starting to sleep' && sleep 3600"]

  # Optional custom restorer. If an init container with this name exists,
  # karb uses it instead of cloning the main container.
  # initContainers:
  #   - name: karb-restorer
```

## Advanced use cases

`karb` is not intended for highly complex backup orchestration. For broad namespace/state backup,
use a platform such as Velero.

You can still use `karb` for app-level backup/restore of a local MinIO deployment.

## Examples

### Minio

- Using the upstream MinIO chart
- Backups/restores full MinIO instance
- No incremental backup logic in this example

```yaml
podAnnotations:
  karb.boa.nu/backup-exec: |
    mc alias set localroot http://localhost:9000 root $MINIO_ROOT_PASSWORD
    now=$(date +%Y-%m-%dT%H%M%S)
    backupfolder=/karb-data/minio-velero/$now
    mkdir -p $backupfolder
    mc mirror localroot/ $backupfolder
  karb.boa.nu/restore-exec: |
    /usr/bin/docker-entrypoint.sh minio server /export -S /etc/minio/certs/ --address 127.0.0.1:9000 --console-address 127.0.0.1:9001 &
    MINIO_PID=$!
    sleep 1
    mc alias set localroot http://localhost:9000 root $MINIO_ROOT_PASSWORD
    read -ra parts <<< $(mc du --quiet localroot/)
    if [[ ${parts[0]} == "0B" && ${parts[1]} == "0" ]]; then
      if [ -d "/karb-data/minio-velero" ]; then
        mc mirror $(ls -d /karb-data/minio-velero/* | sort | tail -n 1) localroot/
        echo "restored latest"
      else
        echo "not restoring since there was nothing backed up"
      fi
    else
      echo "Minio contains data already, not restoring"
    fi
    kill $MINIO_PID
```

### Gitlab Helm chart (backup only)

```yaml
gitlab:
  toolbox:
    enabled: true
    annotations:
      karb.boa.nu/backup-exec: |
        gitlab-rake gitlab:backup:create
        mv /srv/gitlab/tmp/backups/* /karb-data/
        cp -f /srv/gitlab/config/secrets.yml /karb-data/
      karb.boa.nu/restore-exec: |
        echo "not restoring"
```
