#!/usr/bin/env python3
"""Prints host and container CPU counters as JSON; run.sh takes one before and one after each measurement."""
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path


def cgroup_usage(container):
    cid = subprocess.run(['docker', 'inspect', '-f', '{{.Id}}', container], capture_output=True, text=True, check=False).stdout.strip()
    stat = Path(f'/sys/fs/cgroup/system.slice/docker-{cid}.scope/cpu.stat')
    if not cid or not stat.exists():
        return None
    return int(next(line.split()[1] for line in stat.read_text().splitlines() if line.startswith('usage_usec')))


def vm_cpu_ns():
    """CPU time per libvirt VM, keyed by a hash of its name so results carry no host details."""
    out = subprocess.run(['virsh', 'domstats', '--cpu-total'], capture_output=True, text=True, check=False).stdout
    vms, name = {}, None
    for line in out.splitlines():
        if line.startswith('Domain:'):
            name = hashlib.sha256(line.split("'")[1].encode()).hexdigest()[:12]
        elif 'cpu.time=' in line and name:
            vms[name] = int(line.split('=')[1])
    return vms


print(json.dumps({
    'time': time.time(),
    'loadavg': Path('/proc/loadavg').read_text().split()[:3],
    'governor': Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read_text().strip(),
    'host_cpu_jiffies': [int(x) for x in Path('/proc/stat').read_text().splitlines()[0].split()[1:]],
    'vm_cpu_ns': vm_cpu_ns(),
    'container_cpu_usec': {c: cgroup_usage(c) for c in sys.argv[1:]},
}))
