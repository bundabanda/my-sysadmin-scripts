#!/bin/bash

N=5
LOGFILE="monitor.log"

if ! touch "$LOGFILE"; then
    echo "Ошибка: невозможно создать файл $LOGFILE" >&2
    exit 1
fi

for i in $(seq 1 3); do
    echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---" >> "$LOGFILE"
    free -h >> "$LOGFILE"
    df -h >> "$LOGFILE"
    uptime >> "$LOGFILE"
    sleep "$N"
done
