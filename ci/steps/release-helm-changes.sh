#!/bin/bash
set -e

required_missing=()

test "$RELEASE_CHANNEL"     || required_missing+=('RELEASE_CHANNEL')
test "$RELEASE_HELM_CHART"  || required_missing+=('RELEASE_HELM_CHART')
test "$RELEASE_HELM_NAME"   || RELEASE_HELM_NAME=$(basename "$RELEASE_HELM_CHART")
test "$RELEASE_HELM_VALUES" || RELEASE_HELM_VALUES=
test "$RELEASE_NAMESPACE"   || RELEASE_NAMESPACE=

export KUBECONFIG

if [[ ${#required_missing[*]} -gt 0 ]]; then
  printf 'error: missing required variables: %s\n' "${required_missing[*]}" >&2
  exit 1
fi

helm_verb=upgrade
helm_opts=()
chart_path=$(git rev-parse --show-toplevel)/$RELEASE_HELM_CHART

IFS=: values_relpaths=( $RELEASE_HELM_VALUES )
IFS=$' \t\n'

if [[ ! -e $chart_path ]]; then
  printf 'error: chart not found: %s\n' "$RELASE_HELM_CHART" >&2
  exit 1
fi

if [[ $RELEASE_NAMESPACE ]]; then
  helm_opts+=('--namespace' "$RELEASE_NAMESPACE")
fi

if [[ ! $(helm status "$RELEASE_HELM_NAME" "${helm_opts[@]}" 2>/dev/null) ]]; then
  helm_verb=install
fi

for relpath in "${values_relpaths[@]}"; do
  abspath=$(git rev-parse --show-toplevel)/$relpath
  if [[ -e $abspath ]]; then
    helm_opts+=('--values' "$abspath")
  fi
done

while read dep_name dep_version dep_repo dep_status; do
  test "$dep_status" || continue
  if [[ $dep_status != ok ]]; then
    printf 'chart %s: dependency update\n' "$RELEASE_HELM_CHART"
    helm dependency update "$chart_path"
    break
  fi
done <<< "$(helm dependency list "$chart_path" | tail -n +2)"

if [[ $RELEASE_NAMESPACE ]] && [[ ! $(kubectl get ns "$RELEASE_NAMESPACE" 2>/dev/null) ]]; then
  printf '%s: create namespace: %s\n' "$RELEASE_HELM_NAME" "$RELEASE_NAMESPACE"
  kubectl create ns "$RELEASE_NAMESPACE"
fi

# helm does not have a native diff command and the output of helm template does
# not attach the namespace passed using -n to resulting resources. this means
# helm template output cannot be passed directly to kubectl diff.
# this workaround wraps the output of helm template in a kustomize directory to allow
# native diffing.
diff_tmpdir=$(mktemp -d -t "$RELEASE_HELM_CHART")
trap "rm -rf $diff_tmpdir" EXIT
helm template "$RELEASE_HELM_NAME" "$chart_path" "${helm_opts[@]}" > "$diff_tmpdir/manifest.yaml"
cat <<EOF > "$diff_tmpdir/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $RELEASE_NAMESPACE
resources:
- manifest.yaml
EOF
diff_contents=$(kubectl diff -k "$diff_tmpdir" || true)

if [[ $diff_contents ]]; then
  printf 'release: %s: helm %s\n' "$RELEASE_HELM_NAME" "$helm_verb"
  helm "$helm_verb" "$RELEASE_HELM_NAME" "$chart_path" "${helm_opts[@]}"
  test -z "$RELEASE_NOTES" || RELEASE_NOTES+=$'\n'
  RELEASE_NOTES+=$(printf '[helm:%s=%s]\n\n%s\n' "$RELEASE_HELM_NAME" "$RELEASE_HELM_CHART" "$diff_contents")
else
  printf 'skip: %s\n' "$RELEASE_HELM_NAME"
fi
