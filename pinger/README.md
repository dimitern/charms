# Pinger

Pinger is a simple network connectivity checker charm. It is intended to be
deployed with multiple units on all machines you will be using later for a
complex deployment (e.g. OpenStack or Big Data), in order to quickly verify the
connectivity between those machines works as expected.

## Overview

Each Pinger unit will use `ping(8)` to verfiy it can successfully connect each
other peer's addresses, and any configured `extra-targets`. Those checks will be
performed regularly (on changing config or number of peers, as well as every 5
minutes).

After each peer unit performs its checks, a summary will be provided in the
status of the Pinger application. For example, "active OK (all 42 reachable)"
when no connectivity issues were found, or e.g. "blocked FAIL (1 or 42
unreachable)".

All checks and their results are logged. On failure, check the unit log:

```
juju debug-log -i unit-pinger-0 --replay --no-tail -l ERROR
```

(change `unit-pinger-0` to the see a different unit).

Additionally, inside each unit's charm directory there's a `ping.log` file with
all the details ping(8) produced. Get that log like this:

```
juju run --unit pinger/0 -- 'cat /var/lib/juju/agents/unit-pinger-0/charm/ping.log'
```

(change both `pinger/0` and `unit-pinger-0` to see the log of another unit).

## Usage

Deploy to a given machine (e.g. a MAAS node called 'node-42'), like this:

```
juju deploy pinger --to node-42
```

Instead of placement with --to, you can also use other criteria, like
constraints and/or endpoint bindings:

```
juju deploy pinger --constraints 'mem=4G tags=os-nodes'
# or e.g.
juju deploy pinger --bind 'ep0=admin-api ep1=public-api'
```

Add more units to new or existing machine, like this:

```
juju add-unit pinger -n 2
# or e.g.
juju add-unit pinger --to node-11
```

Verify the status output for the overall result of all checks:

```
juju status pinger
```

Update the `extra-targets` after deployment:

```
juju config pinger extra-targets='google.com 10.14.0.1 8.8.8.8'
```

You can also do the same during deployment:

```
juju deploy pinger --config=~/os-pinger-config.yaml
```

Where `~/os-pinger-config.yaml` is a path to a YAML configuration file. An
example config can look like this (for completeness both settings are included):

```yaml
pinger:
    extra-targets: "google.com 10.14.0.1 8.8.8.8"
```

## Configuration

The following configuration settings are supported:
    
    * `extra-targets`: a space-delimited list of IP addresses or hostnames to
      check by each peer, in addition to all addresses of each peer. Empty by
      default.

## Actions

As of this writing, this layer does not define any actions.

# Contact Information

## Maintainer

- Dimiter Naydenov <dimiter.naydenov@canonical.com>
