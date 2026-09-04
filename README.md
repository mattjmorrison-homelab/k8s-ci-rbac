# k8s-ci-rbac

Per-consumer CI RBAC (ServiceAccount + Role/RoleBinding), deployed as
its own Application -- independently of any consumer's own chart.

## Why this is a separate repo

`actions-helm`'s shared CI check (used by every `k8s-` repo) does a
server-side `kubectl apply --dry-run=server` against the real cluster.
That still goes through full RBAC authorization, so the identity
running it needs real create/patch permissions -- which means the
`<name>-ci` ServiceAccount and its RoleBindings have to already exist
*live* before that check can pass.

If a consumer's own chart is what creates that RBAC (the
`k8s-lib-ci-rbac` library chart's intended usage), the very first PR
that adds it can never pass its own dry-run check: the permission it
needs is granted by that same PR, which hasn't been merged/synced yet.
No ordering of commits fixes this -- it's a self-reference, not a race.

This repo breaks that by owning every consumer's CI RBAC itself,
deployed independently. A consumer's dry-run check then depends on
RBAC created by *this* repo's own sync, not by anything in its own PR.

## Adding a new consumer

Add an entry to `manifests/values.yaml`'s `consumers` list:

```yaml
consumers:
  - name: <repo>-ci
    namespace: <namespace the repo's chart deploys to>
    rules:
      - apiGroups: [""]
        resources: ["configmaps", "services"]
      - apiGroups: ["apps"]
        resources: ["deployments"]
```

`rules` should list only the exact `apiGroups`/`resources` pairs that
consumer's own chart actually renders (check `kind:`/`apiVersion:`
across its `manifests/templates/`) -- not a wildcard. This
ServiceAccount gets real (if short-lived, dry-run-only in practice)
create/patch access to whatever's listed, so scope it to what the
chart actually needs, nothing more.

If the namespace already hosts another consumer's CI identity (e.g.
`monitoring` hosting both `prometheus-ci` and a future
`alertmanager-ci`), just add a second entry with a different `name` --
each gets its own independent ServiceAccount/Role/RoleBinding, no
collision.

Then in the consuming repo's own `.github/workflows/check.yml`, pass
`service-account: <repo>-ci` to `actions-helm` (requires the
[`service-account` input](https://github.com/mattjmorrison-homelab/actions-helm)),
and make sure that repo's own chart does **not** also render CI RBAC of
its own for the same identity -- this repo is the sole owner.

## What each consumer entry generates

- A **ServiceAccount** named `<name>`, in `<namespace>`.
- A **Role** + **RoleBinding** (`<name>-writer`) granting that
  ServiceAccount `get`/`list`/`create`/`patch` on exactly the
  `apiGroups`/`resources` pairs listed in `rules`, scoped to just that
  namespace.
- A **Role** + **RoleBinding** (`<name>-token-issuer`) granting
  `github-runner-workload` (the shared identity every repo's CI runs
  as, in the `github-runner` namespace) permission to mint a
  short-lived (10 minute) token *for* `<name>` specifically --
  `resourceNames` restricted to that one ServiceAccount, nothing else.
  The runner's own identity never gains direct write access; only the
  per-consumer identity does, and only for as long as a freshly minted
  token lasts. The RoleBinding is labeled `ci-namespace: <namespace>`
  for external identification.

No token or secret is ever stored anywhere -- everything here is plain,
declarative Kubernetes RBAC.

## This repo's own CI

No dry-run check here (unlike consumer repos) -- this repo generates
the RBAC that the shared dry-run check itself depends on for every
consumer, so a dry-run against a live namespace here would be
circular. `check.yml` runs `helm lint` instead.

## Related

- `k8s-lib-ci-rbac` -- a Helm library chart providing the same
  ServiceAccount/Role/RoleBinding shape as a named template, for a
  consumer chart to include directly. Hits the exact bootstrap problem
  described above when used that way; this repo is the fix.
