#!/bin/bash
set -e

# ── Entropy fix for WSL2 ──────────────────────────────────────────────────────
# WSL2 caps /proc/sys/kernel/random/entropy_avail at 256, which causes munged
# to block indefinitely waiting for entropy from /dev/random.
# Passing --seed /dev/urandom tells munged to use urandom directly instead.

start_munge() {
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    chown munge:munge /run/munge /var/run/munge /var/log/munge 2>/dev/null || true
    gosu munge /usr/sbin/munged --seed /dev/urandom
}

if [ "$1" = "slurmdbd" ]
then
    start_munge
    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    {
        . /etc/slurm/slurmdbd.conf
        until echo "SELECT 1" | mysql -h $StorageHost -u$StorageUser -p$StoragePass 2>&1 > /dev/null
        do
            echo "-- Waiting for database to become active ..."
            sleep 2
        done
    }
    echo "-- Database is now active ..."

    exec gosu slurm /usr/sbin/slurmdbd -Dvvv
fi

if [ "$1" = "slurmctld" ]
then
    start_munge    

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."

    until 2>/dev/null >/dev/tcp/slurmdbd/6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    if /usr/sbin/slurmctld -V | grep -q '17.02' ; then
        exec gosu slurm /usr/sbin/slurmctld -Dvvv
    else
        exec gosu slurm /usr/sbin/slurmctld -i -Dvvv
    fi
fi

if [ "$1" = "slurmd" ]
then
    start_munge    

    echo "---> Waiting for slurmctld to become active before starting slurmd..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm Node Daemon (slurmd) ..."
    exec /usr/sbin/slurmd -Dvvv
fi

if [ "$1" = "login" ]
then
    start_munge
    exec tail -f /dev/null
fi

exec "$@"
