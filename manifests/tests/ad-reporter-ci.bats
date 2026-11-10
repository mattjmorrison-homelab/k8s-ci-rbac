#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template ad-reporter-ci-test .)"
  export RENDERED
}

@test "ad-reporter-ci consumer renders a ServiceAccount in the ad-reporter namespace" {
  ns=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "ad-reporter-ci") |
    .metadata.namespace
  ' -)
  [ "$ns" = "ad-reporter" ]
}

@test "ad-reporter-ci-writer Role grants the core apiGroup resources from the plan" {
  resources=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "ad-reporter-ci-writer") |
    (.rules[] | select(.apiGroups[0] == "") | .resources | join(","))
  ' -)
  [ "$resources" = "configmaps,services,serviceaccounts,persistentvolumeclaims" ]
}

@test "ad-reporter-ci-writer Role grants apps/deployments, batch/jobs, external-secrets.io, and networking.k8s.io/ingresses" {
  apps=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "ad-reporter-ci-writer") |
    (.rules[] | select(.apiGroups[0] == "apps") | .resources | join(","))
  ' -)
  [ "$apps" = "deployments" ]

  batch=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "ad-reporter-ci-writer") |
    (.rules[] | select(.apiGroups[0] == "batch") | .resources | join(","))
  ' -)
  [ "$batch" = "jobs" ]

  ext_secrets=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "ad-reporter-ci-writer") |
    (.rules[] | select(.apiGroups[0] == "external-secrets.io") | .resources | join(","))
  ' -)
  [ "$ext_secrets" = "externalsecrets,secretstores" ]

  ingress=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "Role" and .metadata.name == "ad-reporter-ci-writer") |
    (.rules[] | select(.apiGroups[0] == "networking.k8s.io") | .resources | join(","))
  ' -)
  [ "$ingress" = "ingresses" ]
}

@test "ad-reporter-ci-token-issuer RoleBinding is labeled with ci-namespace matching ad-reporter" {
  token_issuer_rb=$(echo "$RENDERED" | awk 'BEGIN{RS="---\n"} /kind: RoleBinding/ && /name: ad-reporter-ci-token-issuer/')
  [[ "$token_issuer_rb" == *"ci-namespace: ad-reporter"* ]]
}

@test "graph-ad-reporter-job and ui-ad-reporter-job ServiceAccounts render in the github-runner namespace" {
  graph_ns=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "graph-ad-reporter-job") |
    .metadata.namespace
  ' -)
  [ "$graph_ns" = "github-runner" ]

  ui_ns=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "ui-ad-reporter-job") |
    .metadata.namespace
  ' -)
  [ "$ui_ns" = "github-runner" ]
}

@test "graph-ad-reporter-job and ui-ad-reporter-job each pull from their own dedicated zot-pull-secret" {
  graph_secret=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "graph-ad-reporter-job") |
    .imagePullSecrets[0].name
  ' -)
  [ "$graph_secret" = "graph-ad-reporter-zot-pull-secret" ]

  ui_secret=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "ui-ad-reporter-job") |
    .imagePullSecrets[0].name
  ' -)
  [ "$ui_secret" = "ui-ad-reporter-zot-pull-secret" ]
}

@test "graph-ad-reporter-job and ui-ad-reporter-job token-issuer RoleBindings are labeled with ci-namespace: github-runner" {
  graph_rb=$(echo "$RENDERED" | awk 'BEGIN{RS="---\n"} /kind: RoleBinding/ && /name: graph-ad-reporter-job-token-issuer/')
  [[ "$graph_rb" == *"ci-namespace: github-runner"* ]]

  ui_rb=$(echo "$RENDERED" | awk 'BEGIN{RS="---\n"} /kind: RoleBinding/ && /name: ui-ad-reporter-job-token-issuer/')
  [[ "$ui_rb" == *"ci-namespace: github-runner"* ]]
}

@test "graph-ad-reporter-job and ui-ad-reporter-job zot-pull-secret ExternalSecrets carry the forceSyncTrigger force-sync annotation" {
  graph_annotation=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ExternalSecret" and .metadata.name == "graph-ad-reporter-zot-pull-secret") |
    .metadata.annotations["force-sync"]
  ' -)
  [ "$graph_annotation" = "2026-11-10-force-refresh-ad-reporter-zot-credentials" ]

  ui_annotation=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ExternalSecret" and .metadata.name == "ui-ad-reporter-zot-pull-secret") |
    .metadata.annotations["force-sync"]
  ' -)
  [ "$ui_annotation" = "2026-11-10-force-refresh-ad-reporter-zot-credentials" ]
}
