# penguin-tools

`penguin-tools` is a standalone Nix flake for building Penguin guest tools and
publishing the `penguin-tools.tar.gz` release artifact consumed by Penguin's
Docker image build.

## CI/CD

The GitHub Actions workflow expects:

- a self-hosted `rehosting-arc` runner
- a `CACHIX_AUTH_TOKEN` secret for the `rehosting-tools` Cachix cache
- Nix installed by `cachix/install-nix-action`

For fast repeat builds on the shared ARC node, `rehosting-arc` should expose a
persistent `/nix` mount in the runner container, similar to `smallworld-arc`.
Keep Cachix enabled as the cross-runner and cold-start cache; the local `/nix`
mount handles repeated builds on the same runner node.

Recommended `rehosting-arc` runner changes:

```yaml
initContainers:
  - name: init-nix-store
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /nix && chown -R 1001:1001 /nix"]
    securityContext:
      privileged: true
    volumeMounts:
      - name: rehosting-shared-nix-store
        mountPath: /nix

containers:
  - name: runner
    volumeMounts:
      - name: rehosting-shared-nix-store
        mountPath: /nix

volumes:
  - name: rehosting-shared-nix-store
    hostPath:
      path: /shared-nix-store
      type: DirectoryOrCreate
```

Notes:

- The existing `nodeSelector` for `rehosting.shared-node: "true"` should stay.
- `/home/runner/_shared` is useful for large scratch data, but it does not help
  Nix unless the runner mounts a persistent path at `/nix`.
- The runner currently uses uid/gid `1001`, so the mounted `/nix` path must be
  writable by that user.
