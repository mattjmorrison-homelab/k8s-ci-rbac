#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template claude-prompt-runner-job-test .)"
  export RENDERED
}

@test "claude-prompt-runner-job ServiceAccount renders in the github-runner namespace" {
  ns=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "claude-prompt-runner-job") |
    .metadata.namespace
  ' -)
  [ "$ns" = "github-runner" ]
}

@test "claude-prompt-runner-job pulls from its own dedicated zot-pull-secret" {
  secret=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ServiceAccount" and .metadata.name == "claude-prompt-runner-job") |
    .imagePullSecrets[0].name
  ' -)
  [ "$secret" = "claude-prompt-runner-zot-pull-secret" ]
}

@test "claude-prompt-runner-job token-issuer RoleBinding is labeled with ci-namespace: github-runner" {
  rb=$(echo "$RENDERED" | awk 'BEGIN{RS="---\n"} /kind: RoleBinding/ && /name: claude-prompt-runner-job-token-issuer/')
  [[ "$rb" == *"ci-namespace: github-runner"* ]]
}

@test "claude-prompt-runner-job zot-pull-secret ExternalSecret carries the forceSyncTrigger force-sync annotation" {
  annotation=$(echo "$RENDERED" | yq eval-all '
    select(.kind == "ExternalSecret" and .metadata.name == "claude-prompt-runner-zot-pull-secret") |
    .metadata.annotations["force-sync"]
  ' -)
  [ "$annotation" = "2026-11-23-add-claude-prompt-runner-job" ]
}
