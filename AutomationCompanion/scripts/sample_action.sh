#!/usr/bin/env bash
# Sample automation script executed by macOS Trigger Service

echo "=========================================="
echo "Automated Task Executed Successfully!"
echo "Trigger Key:         ${TRIGGER_KEY:-N/A}"
echo "Trigger Press Count: ${TRIGGER_PRESS_COUNT:-1}"
echo "Trigger Timestamp:   ${TRIGGER_TIMESTAMP:-N/A}"
echo "Arguments Passed:    $@"
echo "System Uptime:       $(uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes."}')"
echo "=========================================="

exit 0
