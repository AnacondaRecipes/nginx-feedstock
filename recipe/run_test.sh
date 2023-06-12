#!/bin/bash

set -e
set +x

nginx -h

if [[ "${target_platform}" == linux-aarch64 ]]; then
   # Skip testing on aarch64 because 'ps' is not found
   exit 0
fi

if [[ -n "$TERM" && "$TERM" != dumb ]]; then
    txtund=$(tput sgr 0 1)          # underline
    txtbld=$(tput bold)             # bold
    bldred=${txtbld}$(tput setaf 1) # red
    bldgre=${txtbld}$(tput setaf 2) # green
    bldyel=${txtbld}$(tput setaf 3) # yellow
    bldblu=${txtbld}$(tput setaf 4) # blue
    txtcya=$(tput setaf 6)          # cyan
    bldwht=${txtbld}$(tput setaf 7) # white
    txtrst=$(tput sgr0)             # reset
fi

ERROR=0
SUCCESS=0

TMP_DIR=$(mktemp -d)
chmod 777 $TMP_DIR

pidof() {
    local pids=$(ps axc | awk "{if (\$5==\"$1\") print \$1}" | tr '\n' ' ')
    if [[ -n $pids ]]; then
        echo "$pids"
    else
        return 1;
    fi
}

die() {
    sleep 3
    pidof nginx && pkill nginx
    sleep 1
    pidof nginx && pkill -9 nginx
    echo -e "$@"
}

prepare_config() {
    # Copy configs to /tmp directory for testing instead of using those under $PREFIX.
    # This avoids problems when $PREFIX begins with /root, which prevents
    # default-site from being accessible during testing if it is under $PREFIX.
    cp -R $PREFIX/etc/nginx/* $TMP_DIR

    # Adapted from: https://github.com/tensorflow/tensorboard/blob/1.9.0/tensorboard/pip_package/build_pip_package.sh
    if [ "$(uname)" = "Darwin" ]; then
        sedi="sed -i ''"
    else
        sedi="sed -i"
    fi

    $sedi "s~etc/nginx/default-site~${TMP_DIR}/default-site~g" \
        "${TMP_DIR}/sites.d/default-site.conf"
}

http_test() {
    URL=$1
    UPID=`pidof nginx`
    if [ "$UPID" != "" ]; then
        echo -e "${bldgre}>>> Spawned PID $UPID, running tests${txtrst}"
        sleep 5
        curl -fI $URL
        RET=$?
        if [ $RET != 0 ]; then
            die "${bldred}>>> Error during curl run${txtrst}"
            ERROR=$((ERROR+1))
        else
            SUCCESS=$((SUCCESS+1))
        fi
        die "${bldyel}>>> SUCCESS: Done${txtrst}"
    else
        die "${bldred}>>> ERROR: nginx did not start${txtrst}"
        ERROR=$((ERROR+1))
    fi

    rm -rf $TMP_DIR
}

test_nginx_process() {
    echo -e "${bldyel}================== TESTING =====================${txtrst}"
    echo -e "${bldyel}>>> Preparing nginx config${txtrst}"
    prepare_config

    echo -e "${bldyel}>>> Spawning nginx${txtrst}"
    nginx -c "${TMP_DIR}/nginx.conf" -V
    nginx -c "${TMP_DIR}/nginx.conf" -t
    coproc nginx -c "${TMP_DIR}/nginx.conf"
    http_test "http://localhost:8080/"

    echo -e "${bldyel}===================== DONE =====================${txtrst}\n\n"
}

nginx -V
nginx -t

if [[ $(uname -s) == Linux ]]; then
    test_nginx_process
fi

if [ $ERROR -ge 1 ]; then
    echo "${bldred}>>> $ERROR FAILED${txtrst}"
    set -x
    exit 1
fi

echo "${bldgre}>>> $SUCCESS SUCCESSFUL${txtrst}"
set -x
exit 0
