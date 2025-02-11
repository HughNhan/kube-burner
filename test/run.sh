#!/bin/bash -ex

source base.sh

set -e
setup-kind
setup-prometheus
rc=0
uuid=$(uuidgen)

check_ns() {
  log "Checking the number of namespaces labeled with ${1} is ${2}"
  if [[ $(kubectl get ns -l ${1} -o name | wc -l) != ${2} ]]; then
    log "Number of namespaces labeled with ${1} less than expected"
    rc=1
  fi
}

check_destroyed_ns() {
  log "Checking namespace ${1} has been destroyed"
  if [[ $(kubectl get ns -l ${1} -o name | wc -l) != 0 ]]; then
    log "Namespaces labeled with ${1} not destroyed"
    rc=1
  fi
}

check_running_pods() {
  local running_pods=0
  local pods=0
  namespaces=$(kubectl get ns -l ${1} --no-headers | awk '{print $1}')
  for ns in ${namespaces}; do
    pods=$(kubectl get pod -n ${ns} | grep -c Running)
    running_pods=$((running_pods + pods))
  done
  if [[ ${running_pods} != ${2} ]]; then
    log "Running pods in namespaces labeled with ${1} different from expected"
    rc=1
  fi
}

check_files() {
  for f in collected-metrics/top2PrometheusCPU.json collected-metrics/prometheusRSS.json collected-metrics/prometheusRSS.json collected-metrics/podLatencyMeasurement-namespaced.json collected-metrics/podLatencyQuantilesMeasurement-namespaced.json; do
    log "Checking file ${f}"
    if [[ ! -f $f ]]; then
      log "File ${f} not present"
      rc=1
      continue
    fi
    cat $f | jq .
  done
}

test_init_checks() {
  check_files
  check_ns kube-burner-job=namespaced,kube-burner-uuid=${uuid} 10
  check_running_pods kube-burner-job=namespaced,kube-burner-uuid=${uuid} 10
  timeout 500 kube-burner init -c kube-burner-delete.yml --uuid ${uuid} --log-level=debug
  check_destroyed_ns kube-burner-job=not-namespaced,kube-burner-uuid=${uuid}
  log "Running kube-burner destroy"
  kube-burner destroy --uuid ${uuid}
  check_destroyed_ns kube-burner-job=namespaced,kube-burner-uuid=${uuid}
  log "Evaluating alerts"
  kube-burner check-alerts -u http://localhost:9090 -a alert-profile.yaml --start $(date -d "-2 minutes" +%s)
}

log "Running kube-burner init"
timeout 500 kube-burner init -c kube-burner.yml --uuid ${uuid} --log-level=debug -u http://localhost:9090 -m metrics-profile.yaml -a alert-profile.yaml
test_init_checks
log "Running kube-burner init for multiple endpoints case"
timeout 500 kube-burner init -c kube-burner.yml --uuid ${uuid} --log-level=debug -e metrics-endpoints.yaml
test_init_checks
log "Running kube-burner index test with single prometheus endpoint"
kube-burner index -c kube-burner-index-single-endpoint.yml -u http://localhost:9090 -m metrics-profile.yaml
log "Running kube-burner index test with metric-endpoints yaml"
kube-burner index -c kube-burner.yml -e metrics-endpoints.yaml
kube-burner index -c kube-burner-index-multiple-endpoint.yml
exit ${rc}
