#!/bin/bash

N=5
for i in $(seq 1 3); do
    echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---" >> monitor.log
    free -h >> monitor.log
    df -h >> monitor.log
    uptime >> monitor.log
    sleep "$N"
done
