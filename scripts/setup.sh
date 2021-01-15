#!/bin/bash

# Check if lpdtest has been registered
LAVA_API_TOKEN=$(lava-server manage tokens list --user lpdtest --csv | awk -F "\"*,\"*" '{if (NR==2) {print $2}}')

if [[ -z "$LAVA_API_TOKEN" ]]; then
    # Set the lpdtest user's API token
    LAVA_API_TOKEN=$(lava-server manage tokens add --user lpdtest)
fi

AUTH_LIST=$(lava-tool auth-list)

if [[ "$AUTH_LIST" == *"No tokens found"* ]]; then
    lava-tool auth-add http://lpdtest:${LAVA_API_TOKEN}@localhost --no-check
fi

# Add x86-64 QEMU devices
lava-server manage device-types details aws-ec2_qemu-x86_64
if [[ $? != 0 ]]; then
    lava-server manage device-types add aws-ec2_qemu-x86_64
    lava-server manage devices add  --device-type aws-ec2_qemu-x86_64 --worker worker0 x86_64_aws-ec2_qemu01
fi

# Add LAVA original x86-64 QEMU devices
lava-server manage device-types details qemu
if [[ $? != 0 ]]; then
    lava-server manage device-types add qemu
    lava-server manage devices add  --device-type qemu --worker worker0 qemu-01
fi
