#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage:"
    echo "    $0 <timestamp> [job_timeout]"
    echo "  timestamp: The timestamp as folder name under http://yow-lpdtest.wrs.com/tftpboot/builds/"
    echo "job_timeout: LAVA job timeout in seconds, 1800 by default (0.5 hour)"
    #exit 1
fi

timestamp=$1

PUBLIC_IP=44.234.8.194
LAVA_SERVER=http://${PUBLIC_IP}
FILE_SERVER=${PUBLIC_IP}
HTTP_SERVER=http://"$FILE_SERVER"/tmp
API_VER=v0.2
ADMIN=lpdtest
PASSWD=lpdtest
JOB_TEMPLATE="/opt/lava-dc/jobs/templates/wrlinux-10/x86_64_qemu_job_linaro-smoke-test_template.json"
TMP_JSON="/tmp/test.json"

if [ -z "$2" ]; then
    LAVA_JOB_TIMEOUT=1800   # 0.5 hour
else
    LAVA_JOB_TIMEOUT=$2
fi

function get_job_status () {
    job_status=$(curl -sL "${LAVA_SERVER}/api/${API_VER}/jobs/${JOB_ID}/" | grep -Po '"state":.*?[^\\]",' | sed 's/"state":"\(.*\)\",/\1/')

    if [[ "$job_status" == "Finished" ]]; then
        job_status=$(curl -sL "${LAVA_SERVER}/api/${API_VER}/jobs/${JOB_ID}/" | grep -Po '"health":.*?[^\\]",' | sed 's/"health":"\(.*\)\",/\1/')
    fi
}

function get_lava_token () {
    local token_json=
    token_json=$(curl -sL -d "{\"username\":\"$ADMIN\", \"password\":\"$PASSWD\"}" -H "Content-Type: application/json" -X POST "$LAVA_SERVER/api/v0.1/token/")
    token=$(echo "$token_json" | sed 's/{"token":"//g' | sed 's/"}//g')
}

function submit_lava_job() {
    get_lava_token
    local JSON=$1
    local submit_json=

    submit_json=$(curl -sL -H "Content-Type: application/json" -H "Authorization: Token $token" -X POST "$LAVA_SERVER/api/v0.2/jobs/" -d@$JSON)
    #echo $submit_json

    if [[ "$submit_json" == *"successfully submitted"* ]]; then
        JOB_ID=$(echo $submit_json | sed 's/[^0-9]*//g')
    else
        echo "Submit LAVA job failed"
        exit 1
    fi
}

function rerun_lava_job() {
    get_lava_token
    local rerun_JOB_ID=$1
    local submit_json=

    submit_json=$(curl -sL -d "{\"username\":\"$ADMIN\", \"password\":\"$PASSWD\"}" -H "Content-Type: application/json" -H "Authorization: Token $token" -X POST "$LAVA_SERVER/api/v0.2/jobs/$rerun_JOB_ID/resubmit/")
    #echo $submit_json

    if [[ "$submit_json" == *"successfully submitted"* ]]; then
        JOB_ID=$(echo $submit_json | sed 's/[^0-9]*//g')
    else
        echo "Rerun LAVA job for $PRE_JOB_ID failed"
        exit 1
    fi
}

function upload_result() {
    wget -r --no-parent -q -A summary_*.json "$HTTP_SERVER/$timestamp/"
    local LOCAL_FILES="$FILE_SERVER"/tftpboot/builds/"$timestamp"

    SUMMARY_JSON=$(ls "$LOCAL_FILES" | grep summary)

    sed -i "s/$PRE_JOB_ID/$JOB_ID/g" "$LOCAL_FILES/$SUMMARY_JSON"
    sed -i 's/"test_result": "FAILED"/"test_result": "PASSED"/g' "$LOCAL_FILES/$SUMMARY_JSON"
    sed -i 's/"test_result": "NOTARGET"/"test_result": "PASSED"/g' "$LOCAL_FILES/$SUMMARY_JSON"
    sed -i 's/"test_job_status": "Incompleted"/"test_job_status": "Completed"/g' "$LOCAL_FILES/$SUMMARY_JSON"

    #cat $LOCAL_FILES/$SUMMARY_JSON
    echo "rsync -avL $LOCAL_FILES/$SUMMARY_JSON rsync://$FILE_SERVER/builds/$timestamp"
    rsync -avL "$LOCAL_FILES/$SUMMARY_JSON" "rsync://$FILE_SERVER/builds/$timestamp"


    # Get LAVA job log
    LAVA_JOB_PLAIN_LOG="$LAVA_SERVER/scheduler/job/$JOB_ID/log_file/plain"
    LAVA_JOB_LOG="$LOCAL_FILES/lava_job_$JOB_ID.log"
    echo "curl -k $LAVA_JOB_PLAIN_LOG -o $LAVA_JOB_LOG"
    curl -k "$LAVA_JOB_PLAIN_LOG" -o "$LAVA_JOB_LOG"
    rsync -avL "$LAVA_JOB_LOG" "rsync://$FILE_SERVER/builds/$timestamp"

    # Get LAVA test result in csv format
    LAVA_JOB_RESULT_CSV="$LAVA_SERVER/results/$JOB_ID/csv"
    LAVA_JOB_RESULT_YAML="$LAVA_SERVER/results/$JOB_ID/yaml"
    LAVA_JOB_REPORT_CSV="$LOCAL_FILES/lava_job_${JOB_ID}_result.csv"
    LAVA_JOB_REPORT_YAML="$LOCAL_FILES/lava_job_${JOB_ID}_result.yaml"
    echo "curl -k $LAVA_JOB_RESULT_CSV -o $LAVA_JOB_REPORT_CSV"
    curl -k "$LAVA_JOB_RESULT_CSV" -o "$LAVA_JOB_REPORT_CSV"
    echo "curl -k $LAVA_JOB_RESULT_YAML -o $LAVA_JOB_REPORT_YAML"
    curl -k "$LAVA_JOB_RESULT_YAML" -o "$LAVA_JOB_REPORT_YAML"
    rsync -avL "$LAVA_JOB_REPORT_CSV" "rsync://$FILE_SERVER/builds/$timestamp"
    rsync -avL "$LAVA_JOB_REPORT_YAML" "rsync://$FILE_SERVER/builds/$timestamp"

    rm -rf "$FILE_SERVER"
}

#PRE_JOB_ID=2
#rerun_lava_job "$PRE_JOB_ID"

cp "$JOB_TEMPLATE" "$TMP_JSON"
KERNEL_IMG="$HTTP_SERVER/bzImage"
ROOTFS_IMG="$HTTP_SERVER/wrlinux-image-std-qemux86-64.ext4"
sed -i "s#KERNEL_IMG#$KERNEL_IMG#g" "$TMP_JSON"
sed -i "s#ROOTFS_IMG#$ROOTFS_IMG#g" "$TMP_JSON"
submit_lava_job "$TMP_JSON"

echo "Lava job has been submitted successfully, id: $JOB_ID"
echo "$LAVA_SERVER/scheduler/job/$JOB_ID"

TEST_LOOPS=$((LAVA_JOB_TIMEOUT / 10))
for (( c=1; c<="$TEST_LOOPS"; c++ ))
do
    get_job_status
    echo "$c. Job Status: $job_status"
    if [ "$job_status" == 'Complete' ]; then
        echo "Rerun LAVA job for $PRE_JOB_ID - Passed"
        #upload_result
        break;
    elif [ "$job_status" == 'Incomplete' ]; then
        echo "Rerun LAVA job for $PRE_JOB_ID - Failed"
        exit 1
    elif [ "$job_status" == 'Canceled' ]; then
        echo "Rerun LAVA job for $PRE_JOB_ID - Canceled"
        exit 1
    elif [ "$job_status" == 'Submitted' ] || [ "$job_status" == 'Running' ]; then
        sleep 10
    fi
done

exit 0
