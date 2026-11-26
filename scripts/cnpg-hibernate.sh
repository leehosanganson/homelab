#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: %s {on|off|--help}\n' "${0##*/}"
  cat <<'EOF'

Operate on all CloudNativePG clusters across all namespaces in the current
Kubernetes context.
  on    Hibernate healthy clusters. Verify that instance pods are gone and
        the same persistent volume claims (PVCs) remain bound. If a new
        request fails or fails verification, try to cancel it and check recovery.
        If the on command itself fails, manually recheck before shutdown.
  off   Wake ALL clusters, including previously hibernated ones. Verify that
        each cluster is healthy and all its instance pods are ready.

Requires Bash 5+, GNU timeout, kubectl, jq, and the kubectl cnpg plugin. The
plugin and ready, cluster-wide operator must both be 1.28.x, and the plugin
patch must be at least the operator patch. The current context must allow
discovery, changes, and checks.

The script lists its targets and requires you to type yes in a terminal before
making changes. It verifies clusters one at a time, even if no change was
needed. It continues after individual failures and exits nonzero if any fail.

Warning: CNPG plugin mutations target namespace/name and are not atomic with
the preceding UID check. Do not delete and recreate a cluster during this
operation.

CNPG_HIBERNATE_TIMEOUT_SECONDS sets the verification wait per cluster
(default: 300 seconds; positive integer, up to six digits). Cancellation
recovery gets a separate wait of the same length.
EOF
}

if [[ $# == 1 && $1 == --help ]]; then
  usage
  exit 0
fi
if [[ $# != 1 || ( $1 != on && $1 != off ) ]]; then
  usage >&2
  exit 2
fi
readonly action=$1
readonly wait_timeout=${CNPG_HIBERNATE_TIMEOUT_SECONDS:-300}
[[ $wait_timeout =~ ^[1-9][0-9]{0,5}$ ]] || fail 'CNPG_HIBERNATE_TIMEOUT_SECONDS must be a positive integer of up to six digits.'
[[ -t 0 ]] || fail 'Interactive confirmation on a terminal is required.'
(( BASH_VERSINFO[0] >= 5 )) || fail 'Bash 5 or newer is required.'
for dependency in kubectl jq timeout; do
  command -v "$dependency" >/dev/null || fail "Missing dependency: $dependency"
done

readonly -a watchdog=(timeout --kill-after=0.1s)
"${watchdog[@]}" 1s true || fail 'GNU timeout is required.'
context=$("${watchdog[@]}" 15s kubectl config current-context) && [[ -n $context ]] || fail 'No current Kubernetes context.'
readonly context
printf 'Context: %s\n' "$context"
readonly -a kube=(kubectl "--context=$context" --request-timeout=15s)
readonly -a bounded_kube=("${watchdog[@]}" 15s "${kube[@]}")
readonly resource=clusters.postgresql.cnpg.io

plugin_version=$("${watchdog[@]}" 15s kubectl cnpg version) || fail 'Cannot run the kubectl cnpg plugin.'
printf 'CNPG plugin: %s\n' "$plugin_version"
patch_pattern='(0|[1-9][0-9]*)'
plugin_pattern="(^|[[:space:]{])Version:v?1\.28\.${patch_pattern}(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?([[:space:]}]|$)"
[[ $plugin_version =~ $plugin_pattern ]] || fail 'Expected a CloudNativePG 1.28.x plugin release.'
plugin_patch=${BASH_REMATCH[2]}
plugin_help=$("${watchdog[@]}" 15s kubectl cnpg hibernate "$action" --help) &&
  [[ $plugin_help == *"kubectl cnpg hibernate $action CLUSTER"* ]] ||
  fail "CNPG plugin does not advertise hibernate $action."

operator=$("${bounded_kube[@]}" get deployment cnpg-controller-manager -n cnpg-system -o json) ||
  fail 'Cannot read the CNPG operator Deployment.'
operator_image=$(jq -er '.spec.template.spec.containers[] | select(.name == "manager") | .image' <<< "$operator") ||
  fail 'Cannot determine the CNPG operator image.'
printf 'CNPG operator: %s\n' "$operator_image"
operator_pattern="/cloudnative-pg:1\.28\.${patch_pattern}(@sha256:[[:xdigit:]]+)?$"
[[ $operator_image =~ $operator_pattern ]] || fail 'This helper expects a CNPG 1.28.x operator release.'
operator_patch=${BASH_REMATCH[1]}

patch_is_older() {
  local LC_ALL=C
  # Canonical decimal strings can be ordered without integer overflow.
  (( ${#1} < ${#2} )) || { (( ${#1} == ${#2} )) && [[ $1 < $2 ]]; }
}
if patch_is_older "$plugin_patch" "$operator_patch"; then
  fail "CNPG plugin 1.28.$plugin_patch is older than the CNPG operator 1.28.$operator_patch."
fi
jq -e '
  .spec.replicas as $desired |
  $desired > 0 and .status.observedGeneration == .metadata.generation and
  .status.updatedReplicas == $desired and .status.replicas == $desired and
  .status.availableReplicas == $desired
' <<< "$operator" >/dev/null || fail 'The CNPG operator Deployment is not ready.'
# CNPG 1.28 selects the cache scope from the environment before loading its ConfigMap/Secret.
jq -e '
  .spec.template.spec.containers[] | select(.name == "manager") |
  ((.envFrom // []) | length == 0) and
  all(.env[]? | select(.name == "WATCH_NAMESPACE");
      .valueFrom == null and (.value // "") == "")
' <<< "$operator" >/dev/null || fail 'CNPG operator WATCH_NAMESPACE is non-empty or unresolved (including envFrom); all namespaces are required.'
printf 'CNPG operator Deployment is ready and configured to watch all namespaces.\n'

targets=$("${bounded_kube[@]}" get "$resource" -A -o json | jq -r '
  .items[] | [.metadata.namespace, .metadata.name, .metadata.uid] | @tsv
') || fail 'Cannot discover CNPG Clusters across all namespaces.'
if [[ -z $targets ]]; then
  printf 'No CNPG Clusters found.\n'
  exit 0
fi

printf 'Targets for hibernate %s (wait up to %s seconds per cluster):\n' "$action" "$wait_timeout"
while IFS=$'\t' read -r namespace name uid; do
  printf '  %s/%s\n' "$namespace" "$name"
done <<< "$targets"
if [[ $action == off ]]; then
  printf 'WARNING: off reactivates all hibernated clusters, including those hibernated before this run.\n'
fi
printf 'Type yes to proceed on context %s: ' "$context" >&2
if ! IFS= read -r answer || [[ $answer != yes ]]; then
  fail 'Cancelled; no clusters changed.'
fi

readonly original_cluster=".metadata.uid == \$uid and .metadata.deletionTimestamp == null"
readonly hibernation_state='(.metadata.annotations["cnpg.io/hibernation"] // "off")'
readonly healthy='.status.phase == "Cluster in healthy state" and .spec.instances > 0 and
                  .status.readyInstances == .spec.instances'
readonly hibernation_condition='.type == "cnpg.io/hibernation"'
readonly pvc_inventory='[.items[] | {name: .metadata.name, uid: .metadata.uid, volume: .spec.volumeName,
                                       phase: .status.phase, deleting: .metadata.deletionTimestamp}] | sort_by(.name)'

now_us() {
  local now=$EPOCHREALTIME
  printf '%s\n' "${now/./}"
}

before_deadline() {
  local deadline=$1
  shift
  local remaining=$((deadline - $(now_us)))
  (( remaining > 0 )) || return 124
  local duration
  printf -v duration '%d.%06ds' "$((remaining / 1000000))" "$((remaining % 1000000))"
  LC_ALL=C "${watchdog[@]}" "$duration" "$@"
}

verify_cluster() {
  local requested=$1 namespace=$2 name=$3 uid=$4 before=${5:-} required_off_checks=${6:-1}
  local target=$namespace/$name deadline cluster pods pvcs after instances poll_status
  local off_checks=0 off_ready poll_interval=5
  # Pooler pods can share the cluster label but are not database instances.
  local selector="cnpg.io/cluster=$name,cnpg.io/podRole=instance"
  if (( required_off_checks > 1 && wait_timeout < 10 )); then
    # Leave time for a second check even with a short recovery deadline.
    printf -v poll_interval '%d.%d' "$((wait_timeout / 2))" "$((wait_timeout % 2 * 5))"
  fi
  deadline=$(($(now_us) + wait_timeout * 1000000))
  while (( $(now_us) < deadline )); do
    cluster=$(before_deadline "$deadline" "${kube[@]}" get "$resource" "$name" -n "$namespace" -o json) || break
    if ! before_deadline "$deadline" jq -e --arg uid "$uid" "$original_cluster" <<< "$cluster" >/dev/null; then
      (( $(now_us) < deadline )) || break
      printf '%s: cluster was replaced, is being deleted, or its identity could not be verified\n' "$target" >&2
      return 1
    fi
    off_ready=no
    if [[ $requested == on ]]; then
      if before_deadline "$deadline" jq -e "
        $hibernation_state == \"on\" and
        any(.status.conditions[]?; $hibernation_condition and .status == \"True\" and .reason == \"Hibernated\")
      " <<< "$cluster" >/dev/null; then
        pods=$(before_deadline "$deadline" "${kube[@]}" get pods -n "$namespace" -l "$selector" -o json) || break
        if before_deadline "$deadline" jq -e '.items == []' <<< "$pods" >/dev/null; then
          pvcs=$(before_deadline "$deadline" "${kube[@]}" get pvc -n "$namespace" -l "cnpg.io/cluster=$name" -o json) || break
          after=$(before_deadline "$deadline" jq -ce "$pvc_inventory" <<< "$pvcs") || break
          (( $(now_us) < deadline )) || break
          if [[ $after != "$before" ]]; then
            printf '%s: PVC inventory changed (claims or volume bindings differ)\n' "$target" >&2
            return 1
          fi
          printf '%s: hibernated; PVCs retained\n' "$target"
          return 0
        fi
      fi
    elif instances=$(before_deadline "$deadline" jq -er "
      select($hibernation_state == \"off\" and ($healthy) and
             (any(.status.conditions[]?; $hibernation_condition) | not)) | .spec.instances
    " <<< "$cluster"); then
      pods=$(before_deadline "$deadline" "${kube[@]}" get pods -n "$namespace" -l "$selector" -o json) || break
      # shellcheck disable=SC2016 # $instances is a jq variable.
      if before_deadline "$deadline" jq -e --argjson instances "$instances" '
        (.items | length) == $instances and
        all(.items[]; .metadata.deletionTimestamp == null and
                      any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      ' <<< "$pods" >/dev/null; then
        (( $(now_us) < deadline )) || break
        off_ready=yes
      fi
    fi
    if [[ $off_ready == yes ]]; then
      off_checks=$((off_checks + 1))
      if (( off_checks >= required_off_checks )); then
        printf '%s: healthy; all instances ready\n' "$target"
        return 0
      fi
    else
      off_checks=0
    fi
    if before_deadline "$deadline" sleep "$poll_interval"; then
      continue
    else
      poll_status=$?
    fi
    (( $(now_us) < deadline )) || break
    printf '%s: sleep failed while verifying hibernate %s (exit %s)\n' "$target" "$requested" "$poll_status" >&2
    return 1
  done
  if (( $(now_us) >= deadline )); then
    printf '%s: timed out waiting for hibernate %s\n' "$target" "$requested" >&2
  else
    printf '%s: could not read resources to verify hibernate %s\n' "$target" "$requested" >&2
  fi
  return 1
}

request_hibernation() {
  local requested=$1 namespace=$2 name=$3
  # The plugin patches by name; the preceding UID check is not atomic with this call.
  "${watchdog[@]}" 15s kubectl cnpg hibernate "$requested" "$name" -n "$namespace" "--context=$context" --request-timeout=15s
}

cancel_new_on() {
  local namespace=$1 name=$2 uid=$3 reason=$4
  local target=$namespace/$name cluster
  if ! cluster=$("${bounded_kube[@]}" get "$resource" "$name" -n "$namespace" -o json) ||
     ! jq -e --arg uid "$uid" "$original_cluster" <<< "$cluster" >/dev/null; then
    printf '%s: cancellation not attempted: original cluster identity is unknown; an on request may be pending\n' "$target" >&2
    return
  fi
  # A failed or timed-out on request can still take effect after this read.
  printf '%s: canceling new on request with off\n' "$target" >&2
  if ! request_hibernation off "$namespace" "$name"; then
    printf '%s: cancellation plugin failed; checking recovery anyway\n' "$target" >&2
  fi
  if verify_cluster off "$namespace" "$name" "$uid" '' 2; then
    if [[ $reason == command_failed ]]; then
      printf '%s: current off/healthy state observed; cancellation is not confirmed\n' "$target" >&2
    else
      printf '%s: cancellation recovery verified; original on request still failed\n' "$target" >&2
    fi
  else
    printf '%s: cancellation recovery failed; an on request may still be pending; inspect the cluster before retrying\n' "$target" >&2
  fi
}

process_cluster() {
  local namespace=$1 name=$2 uid=$3
  local target=$namespace/$name cluster state pvcs before=
  if [[ $action == on ]]; then
    if ! pvcs=$("${bounded_kube[@]}" get pvc -n "$namespace" -l "cnpg.io/cluster=$name" -o json) ||
       ! before=$(jq -ce "$pvc_inventory" <<< "$pvcs") || ! jq -e '
      length > 0 and all(.[]; .uid != null and .phase == "Bound" and .volume != null and .deleting == null)
    ' <<< "$before" >/dev/null; then
      printf '%s: cannot establish a baseline of bound PVCs\n' "$target" >&2
      return 1
    fi
  fi
  if ! cluster=$("${bounded_kube[@]}" get "$resource" "$name" -n "$namespace" -o json) ||
     ! state=$(jq -er --arg uid "$uid" "select($original_cluster) | $hibernation_state" <<< "$cluster"); then
    printf '%s: could not read the original cluster or it is being deleted\n' "$target" >&2
    return 1
  fi
  if [[ $state == "$action" ]]; then
    printf '%s: already set to %s; verifying without mutation\n' "$target" "$action"
    verify_cluster "$action" "$namespace" "$name" "$uid" "$before"
    return
  fi
  if [[ $action == on ]] && { [[ $state != off ]] || ! jq -e "$healthy" <<< "$cluster" >/dev/null; }; then
    printf '%s: cannot request hibernation; cluster must be off, healthy, and have all requested instances ready\n' "$target" >&2
    return 1
  fi
  if ! request_hibernation "$action" "$namespace" "$name"; then
    printf '%s: plugin mutation failed\n' "$target" >&2
    if [[ $action == on ]]; then
      cancel_new_on "$namespace" "$name" "$uid" command_failed
      printf '%s: an in-flight on request may still apply. STOP: manually recheck this cluster before shutdown.\n' "$target" >&2
    fi
    return 1
  fi
  if verify_cluster "$action" "$namespace" "$name" "$uid" "$before"; then
    return 0
  fi
  if [[ $action == on ]]; then
    cancel_new_on "$namespace" "$name" "$uid" verification_failed
  fi
  return 1
}

verified=0
failed=()
while IFS=$'\t' read -r namespace name uid; do
  if process_cluster "$namespace" "$name" "$uid" </dev/null; then
    verified=$((verified + 1))
  else
    failed+=("$namespace/$name")
  fi
done <<< "$targets"

printf 'Hibernate %s: %s verified, %s failed.\n' "$action" "$verified" "${#failed[@]}"
if (( ${#failed[@]} > 0 )); then
  printf '  Failed: %s\n' "${failed[@]}" >&2
  exit 1
fi
