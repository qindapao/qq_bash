#!/usr/bin/env bash

RED() {
    echo -e "\033[40;31m$*\033[0m"
}
GRN() {
    echo -e "\033[40;32m$*\033[0m"
}
YLW() {
    echo -e "\033[40;33m$*\033[0m"
}
BLU() {
    echo -e "\033[40;36m$*\033[0m"
}
exit_print() {
    RED "$*"
    exit 1
}

src_dir=$(pwd)

get_patch_file() {
    local ver=$1
    local subver=$2
    local patch_ver=$3
    patch_ver=$(printf "%03d" "${patch_ver}")
    echo "bash${ver}${subver}-${patch_ver}"
}

wget_file() {
    local link=$1
    BLU "get file ${link}"
    for ((i = 0; i < 3; i++)); do
        wget "${link}" &>/dev/null && break
        sleep 1
    done
}

get_patch() {
    local ver=$1
    local subver=$2
    local patch_ver=$3
    local patch_file=$(get_patch_file "${ver}" "${subver}" "${patch_ver}")
    local patch_link="https://mirrors.tools.xx.com/gnu/bash/bash-${ver}.${subver}-patches/${patch_file}"
    [ -f "${patch_file}" ] && rm -f "${patch_file}"
    wget_file "${patch_link}"
    [ -f "${patch_file}" ] && return 0
    return 1
}

get_src_tar() {
    local ver=$1
    local subver=$2
    local src_tar="bash-${ver}.${subver}.tar.gz"
    local src_tar_link="https://mirrors.tools.xx.com/gnu/bash/${src_tar}"
    [ -f "${src_tar}" ] && rm -f "${src_tar}"
    wget_file "${src_tar_link}"
    [ -f "${src_tar}" ] && return 0
    return 1
}

build_patch_ver() {
    local ver=$1
    local subver=$2
    local patch_ver=$3
    local patch_surffix=""
    [ -n "${patch_ver}" ] && patch_surffix=".${patch_ver}"

    BLU ""
    BLU " === start building version ${ver}.${subver}${patch_surffix} === "
    if [ -n "${patch_ver}" ]; then
        get_patch "${ver}" "${subver}" "${patch_ver}" || {
            RED "get patch fail ${ver}.${subver}${patch_surffix}"
            return 1
        }
        GRN "get patch pass ${ver}.${subver}${patch_surffix}"
        local patch_file=$(get_patch_file "${ver}" "${subver}" "${patch_ver}")
        patch -p0 <"${patch_file}" || {
            RED "apply patch ${patch_file} fail"
            return 1
        }
        GRN "apply ${patch_file} pass"
    fi

    rm -f bash 2>/dev/null
    make clean &>/dev/null
    make distclean &>/dev/null
    chmod +x configure
    BLU "configure"
    ./configure CC=aarch64-target-linux-gnu-gcc --host=aarch64-linux-gnu --build=x86_64-linux-gnu --prefix=/usr/local &>/dev/null
    BLU "make"
    make -j2 &>/dev/null

    if [ ! -f "bash" ]; then
        RED "build ${ver}.${subver}${patch_surffix} fail "
        return 1
    fi

    odir="${src_dir}/bash_bin/bash-${ver}.${subver}${patch_surffix}"
    mkdir -p "${odir}" || exit_print "mkdir fail"
    cp -f bash "${odir}" || exit_print "cp fail"
    md5sum bash | tee "${odir}/md5.txt"

    GRN "build ${ver}.${subver}${patch_surffix} pass "
    return 0
}

build_subver() {
    local ver=$1
    local subver=$2
    BLU ""
    BLU ""
    BLU " ===== start building version ${ver}.${subver} ===== "
    cd "${src_dir}" || exit_print "cd fail"
    local bash_tar_name="bash-${ver}.${subver}"
    local src_tar="${bash_tar_name}.tar.gz"
    [ -f "${src_tar}" ] && rm -f "${src_tar}"
    local src_tar_link="https://mirrors.tools.xx.com/gnu/bash/${src_tar}"
    wget_file "${src_tar_link}"

    rm -rf "./${bash_tar_name}/"
    tar xzf "${src_tar}" || exit_print "extract fail"
    cd "${bash_tar_name}" || exit_print "cd fail"

    build_patch_ver "${ver}" "${subver}" "" || return 1

    for ((patch_ver = 1; patch_ver < 1000; patch_ver++)); do
        build_patch_ver "${ver}" "${subver}" "${patch_ver}" || break
    done

    cd "${src_dir}" || exit_print "cd fail"
    rm -rf ./"${bash_tar_name}"*
}

ver=5
for subver in $(seq 0 3); do
    build_subver 5 "${subver}"
done

cd "${src_dir}" || exit_print "cd fail"
rm -f bash_bin.tar.gz 2>/dev/null
tar czf bash_bin.tar.gz bash_bin/ || exit_print "compress fail"
GRN "all done"

