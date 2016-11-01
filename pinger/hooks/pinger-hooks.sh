#!/bin/bash

set -eua

# $JUJU_HOOK_NAME is only set in debug-hooks sessions (LP Bug http://pad.lv/1503039)
: ${JUJU_HOOK_NAME:=$(basename $0)}

# $PINGER_LOG is the path to the log file used for capturing the ping(8) output.
: ${PINGER_LOG:=$JUJU_CHARM_DIR/ping.log}

# $PINGER_ARGS are the arguments to pass to ping(8), before the target.
# NOTE: This assumes peers use fast local connections, reachable within 50ms.
#       If that's not the case (e.g. in public clouds), the interval should
#       be increased. Also for -i <200ms sudo will be needed to run ping.
: ${PINGER_ARGS:=-c 3 -i 0.05 -w 0.2 -q}

set +a

get-peer-relation-id() {
    echo "${JUJU_RELATION_ID:-$(relation-ids peer || true)}"
}

get-target-names() {
    # public-address in unlikely to be reachable inside the model.
    echo private ep{0..9}
}

get-peer-names() {
    local rid="$(get-peer-relation-id)"
    echo $(relation-list -r $rid | tr '\n' ' ' || true)
}

get-local-target() {
    local target_name=${1?"target_name missing"} value=
    local private_address="$(unit-get private-address || true)"
    case $target_name in
        ep[0-9])
            # network-get returns the private address for extra-bindings not
            # bound explicitly, so treat this case as having no value.
            value="$(network-get $target_name --primary-address || true)"
            [ "$value" = "$private_address" ] && value=""
            ;;
        private)
            value="$private_address"
            ;;
    esac
    echo "$value"
}

get-peer-target() {
    local peer_name=${1?"peer_name missing"}
    local target_name=${2?"target_name missing"}
    local rid="$(get-peer-relation-id)"
    echo "$(relation-get -r $rid ${target_name}-address $peer_name || true)"
}

report-local-targets-to-peers() {
    local values=""
    for target_name in $(get-target-names); do
        local value="$(get-local-target $target_name || true)"
        [ -n "$value" ] && values="${target_name}-address=$value $values"
    done
    local rid="$(get-peer-relation-id)"
    relation-set -r $rid $values || true
}

log-ping() {
    local line="$1"
    echo -e "$line" >> "$PINGER_LOG"
}

reset-ping-log() {
    [ -f "$PINGER_LOG" ] && rm "$PINGER_LOG" || true
}

ping-target() {
    set +u; local target="$1"; set -u # might be empty
    # sudo is necessary when using short interval arg (<200ms).
    if [ -n "$target" ]; then
        sudo ping $PINGER_ARGS $target 2>&1 >> $PINGER_LOG
    fi
}

ping-all-targets() {
    local targets=$(get-target-names)
    local peers=$(get-peer-names)
    local extra=$(config-get extra-targets || true)
    local failed=0 passed=0 value=""

    log-ping "\n==== Started on $(date -R) during hook $JUJU_HOOK_NAME ==="

    for target in $targets; do
        value="$(get-local-target $target)"
        [ -n "$value" ] && status-set maintenance "CHECKING ($JUJU_UNIT_NAME $target address ($value)...)"
        if ping-target "$value"; then
            [ -n "$value" ] && passed=$((passed+1))
        else
            failed=$((failed+1))
            juju-log -l ERROR "FAIL: $JUJU_UNIT_NAME $targes address ($value) unreachable"
        fi

        for peer in $peers; do
            value="$(get-peer-target $peer $target)"
            [ -n "$value" ] && status-set maintenance "CHECKING ($peer $target address ($value)...)"
            if ping-target "$value"; then
                [ -n "$value" ] && passed=$((passed+1))
            else
                failed=$((failed+1))
                juju-log -l ERROR "FAIL: $peer $target address ($value) unreachable"
            fi
        done
    done

    for value in $extra; do
        status-set maintenance "CHECKING (extra-target $value...)"
        if ping-target "$value"; then
            [ -n "$value" ] && passed=$((passed+1))
        else
            failed=$((failed+1))
            juju-log -l ERROR "FAIL: extra-target $value unreachable"
        fi
    done

    log-ping "\n==== Stopped on $(date -R) during hook $JUJU_HOOK_NAME ===="

    if [ "$failed" != "0" ]; then
        status-set blocked "FAIL ($failed of $passed unreachable)"
        return
    fi
    status-set active "OK (all $passed targets reachable)"
}

case $JUJU_HOOK_NAME in
    install|upgrade-charm)
        reset-ping-log
        ;;

    peer-relation-joined)
        report-local-targets-to-peers
        ;;

    update-status|config-changed|peer-relation-changed|peer-relation-departed)
        ping-all-targets
        ;;
esac

exit 0
