#!/usr/bin/env bash

kubectl get pods -A -o=jsonpath='
{range .items[*]}
{"\n"}{.metadata.namespace}{"\t"}{range .status.containerStatuses[*]}{.imageID}{", "}{end}
{end}' | sort | uniq
