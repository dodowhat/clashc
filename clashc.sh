#!/usr/bin/env bash

dirname() {
    # Usage: dirname "path"
    local tmp=${1:-.}

    [[ $tmp != *[!/]* ]] && {
        printf '/\n'
        return
    }

    tmp=${tmp%%"${tmp##*[!/]}"}

    [[ $tmp != */* ]] && {
        printf '.\n'
        return
    }

    tmp=${tmp%/*}
    tmp=${tmp%%"${tmp##*[!/]}"}

    printf '%s\n' "${tmp:-/}"
}

bkr() {
    (nohup "$@" &>/dev/null &)
}

strip_all() {
    # Usage: strip_all "string" "pattern"
    printf '%s\n' "${1//$2}"
}

lstrip() {
    # Usage: lstrip "string" "pattern"
    printf '%s\n' "${1##$2}"
}

test_command() {
    if [[ ! $(command -v $1) ]]; then
        echo "error: $1 command not found"
        exit 1
    fi
}

trim_quotes() {
    # Usage: trim_quotes "string"
    : "${1//\'}"
    printf '%s\n' "${_//\"}"
}

basename() {
    # Usage: basename "path" ["suffix"]
    local tmp

    tmp=${1%"${1##*[!/]}"}
    tmp=${tmp##*/}
    tmp=${tmp%"${2/"$tmp"}"}

    printf '%s\n' "${tmp:-/}"
}

head() {
    # Usage: head "n" "file"
    mapfile -tn "$1" line < "$2"
    printf '%s\n' "${line[@]}"
}

# baseurl="https://github.com"
baseurl="https://ghproxy.com/https://github.com"
api_baseurl="https://api.github.com/repos"

# script_dir=$(dirname $(realpath $0))
config_dir=~/.clashc_runtime
update_dir=${config_dir}/update

process_name_base="clash-linux-amd64-v3"
process_name="${process_name_base}"

clash_path=${config_dir}/${process_name}
clash_update_path=${update_dir}/${process_name}

clash_repo="Dreamacro/clash"
# clash_release_url="${api_baseurl}/${clash_repo}/releases/tags/premium"
clash_release_url="${api_baseurl}/${clash_repo}/releases/latest"

dashboard_name="clash-dashboard"
dashboard_owner="Dreamacro"
# dashboard_name="yacd"
# dashboard_owner="haishanh"

dashboard_repo="${dashboard_owner}/${dashboard_name}"
dashboard_repo_branch="gh-pages"
dashboard_path=${config_dir}/${dashboard_name}
dashboard_update_path=${update_dir}/${dashboard_name}

geoip_name="Country.mmdb"
geoip_path=${config_dir}/${geoip_name}
geoip_update_path_path=${update_dir}/${geoip_name}

# geoip_repo="Dreamacro/maxmind-geoip"
# geoip_release_url="${api_baseurl}/${geoip_repo}/releases/latest"
# geoip_download_url="${baseurl}/${geoip_repo}/releases/latest/download/${geoip_name}"
geoip_repo="Hackl0us/GeoIP2-CN"
geoip_release_url="${api_baseurl}/${geoip_repo}/branches/release"
geoip_download_url="${baseurl}/${geoip_repo}/raw/release/${geoip_name}"

if [[ -d $update_dir ]]; then
    rm -rf $update_dir
fi
mkdir -p $update_dir

config_path=${config_dir}/config.yaml

if [[ ! -f $config_path ]]; then
    echo "mixed-port: 7890" >> $config_path
    echo "external-controller: 127.0.0.1:9090" >> $config_path
    echo "external-ui: ${dashboard_name}" >> $config_path
fi

get_help() {
    printf "Clash command-line management tool\n\n"
    printf "Syntax: clashc [start|stop|status|update|set|get]\n"
    printf "Options:\n"
    format="%3s %-20s %s\n"
    printf "$format" "" "start" "start clash service"
    printf "$format" "" "stop" "stop clash service"
    printf "$format" "" "status" "check clash service status"
    printf "$format" "" "update" "update clash, dashboard, geoip database"
    printf "$format" "" "set [example.yaml]" "apply config file to clash service"
    printf "$format" "" "get [example.txt]" "update config subscription"
    printf "$format" "" "" "the content of example.txt is your subscription url"
}

start_clash() {
    pid=$(pidof $process_name)
    if [ -z $pid ]; then
        bkr $clash_path -d $config_dir
    else
        echo "already running"
        exit 1
    fi
}

stop_clash() {
    pid=$(pidof $process_name)
    if [[ -n $pid ]]; then
        kill -9 $pid
    fi
}

get_external_controller() {
    pattern="external-controller:"
    while IFS= read line || [ -n "$line" ]; do
        line=$(strip_all "$line" "[[:space:]]")
        if [[ $line == ${pattern}* ]]; then
            external_controller=$(lstrip "$line" "$pattern")
        fi
    done < ${config_dir}/config.yaml

    if [[ -n $external_controller ]]; then
        echo $external_controller
        return 0
    else
        return 1
    fi
}

get_status() {
    pid=$(pidof $process_name)
    if [ -z $pid ]; then
        echo "clash not running"
        return 1
    fi

    external_controller=$(get_external_controller)

    if [[ -z $external_controller ]]; then
        echo "no 'external-controller' attribute in ${config_dir}/config.yaml"
        return 1
    fi

    url="${external_controller}/configs"
    curl -sSL $url | jq
}

set_config() {
    pid=$(pidof $process_name)
    if [ -z $pid ]; then
        echo "clash not running"
        exit 1
    fi

    external_controller=$(get_external_controller)

    if [[ -z $external_controller ]]; then
        echo "no 'external-controller' attribute in ${config_dir}/config.yaml"
        exit 1
    fi

    if [[ -z $1 ]]; then
        get_help
        exit 1
    fi
    if [[ ! -f $1 ]]; then
        echo "$1 not exists"
        exit 1
    fi

    config_path=$(realpath $1)
    data="{\"path\":\"${config_path}\"}"
    header="Content-Type:application/json"
    url="${external_controller}/configs"
    status=$(curl -sSL -X PUT $url -H $header --data-raw $data -w "%{http_code}")

    if [[ $? != 0 || $status != "204" ]]; then
        printf "error: $status\n"
    fi
}

test_clash_update() {
    url=$clash_release_url
    release_name=$(curl -sSL $url | jq '.name')

    if [[ $release_name != v* ]]; then
        latest_version=$(lstrip "$(trim_quotes $release_name)" "Premium ")
    else
        latest_version=$release_name
    fi

    if [[ ! -f $clash_path ]]; then
        echo $latest_version
        return 0
    fi

    current_version=$($clash_path -v | awk '{print $2}')
    if [[ $current_version == $latest_version ]]; then
        return 1
    else
        echo $latest_version
    fi
}

get_clash() {
    printf "downloading clash ... \n"

    archive_name="${process_name}-${latest_version}.gz"
    archive_path=${update_dir}/${archive_name}

    if [[ $latest_version != v* ]]; then
        tag="premium"
    else
        tag=$latest_version
    fi

    url="${baseurl}/${clash_repo}/releases/download/${tag}/${archive_name}"
    echo $url
    curl -#SL $url -o $archive_path

    if [[ $? ]]; then
        printf "unpacking clash ... "
        gzip -dc < $archive_path > $clash_update_path
        if [[ $? ]]; then
            rm $archive_path
            printf "success\n"
        else
            printf "error\n"
        fi
    else
        printf "error\n"
    fi
}

update_clash() {
    if [[ -f $clash_update_path ]]; then
        printf "updating clash ... "
        mv -f $clash_update_path $config_dir
        chmod u+x $clash_path
        if [[ $? ]]; then
            printf "success\n"
        fi
    fi
}

test_dashboard_update() {
    if [[ ! -d $dashboard_path ]]; then
        return 0
    fi
    current_version_datetime=$(date -r $dashboard_path +%s)
    url="${api_baseurl}/${dashboard_repo}/branches/${dashboard_repo_branch}"
    latest_version_datetime=$(trim_quotes "$(curl -sSL $url | jq '.commit.commit.committer.date')")
    latest_version_datetime=$(date -d $latest_version_datetime +%s)
    if [[ $current_version_datetime < $latest_version_datetime ]]; then
        return 0
    else
        return 1
    fi
}

get_dashboard() {
    printf "downloading dashboard ... \n"
    dashboard_repo_branch="gh-pages"
    url="${baseurl}/${dashboard_repo}/archive/refs/heads/${dashboard_repo_branch}.zip"
    archive_path="${dashboard_update_path}-${dashboard_repo_branch}.zip"
    curl -#SL $url -o $archive_path
    if [[ $? == 0 ]]; then
        printf "unpacking dashboard ... "
        unzip -qq $archive_path -d $update_dir
        if [[ $? == 0 ]]; then
            mv -f ${dashboard_update_path}-${dashboard_repo_branch} $dashboard_update_path
            rm $archive_path
            printf "success\n"
        else
            printf "error\n"
        fi
    else
        printf "error\n"
    fi
}

update_dashboard() {
    if [[ -d $dashboard_update_path ]]; then
        printf "updating dashboard ... "
        rm -rf $dashboard_path
        mv -f $dashboard_update_path $config_dir
        if [[ $? == 0 ]]; then
            printf "success\n"
        fi
    fi
}

test_geoip_update() {
    if [[ ! -f $geoip_path ]]; then
        return 0
    fi
    current_version_datetime=$(date -r $geoip_path +%s)
    url=$geoip_release_url
    release_info=$(curl -sSL $url)
    if [[ $url == *branches* ]]; then
        latest_version_datetime=$(trim_quotes "$(echo $release_info | jq '.commit.commit.committer.date')")
    else
        latest_version_datetime=$(trim_quotes "$(echo $release_info | jq '.published_at')")
    fi
    latest_version_datetime=$(date -d $latest_version_datetime +%s)
    if [[ $current_version_datetime < $latest_version_datetime ]]; then
        return 0
    else
        return 1
    fi
}

get_geoip() {
    printf "downloading geoip ... \n"
    url=$geoip_download_url
    curl -#SL $url -o $geoip_update_path_path
}

update_geoip() {
    if [[ -f $geoip_update_path_path ]]; then
        printf "updating geoip ... "
        mv -f $geoip_update_path_path $config_dir
        if [[ $? == 0 ]]; then
            printf "success\n"
        fi
    fi
}

test_downloaded_update() {
    if [[ -f $clash_update_path ]] || [[ -d $dashboard_update_path ]] || [[ -f $geoip_update_path_path ]]; then
        return 0
    else
        return 1
    fi
}

update() {
    test_command jq
    test_command gzip
    test_command unzip

    printf "checking clash update ... "
    latest_version=$(test_clash_update)
    if [[ -n $latest_version ]]; then
        printf "success\n"
        get_clash
    else
        printf "alreay up to date\n"
    fi

    printf "checking dashboard update ... "
    if test_dashboard_update; then
        printf "success\n"
        get_dashboard
    else
        printf "alreay up to date\n"
    fi

    printf "checking geoip update ... "
    if test_geoip_update; then
        printf "success\n"
        get_geoip
    else
        printf "alreay up to date\n"
    fi

    if test_downloaded_update; then
        stop_clash
        update_clash
        update_dashboard
        update_geoip
    fi
}

get_config() {
    if [[ -z $1 ]]; then
        get_help
        exit 1
    fi
    if [[ ! -f $1 ]]; then
        echo "$1 not exists"
        exit 1
    fi

    abs_path=$(realpath $1)
    basename=$(basename $abs_path .txt)

    # target_dir=$(dirname $abs_path)
    # target_path=${target_dir}/${basename}.yaml
    if [[ -z "$2" ]]; then
        target_path="${basename}.yaml"
    else
        target_path=$2
    fi

    url=$(head 1 $abs_path)
    url=$(strip_all "$url" "[[:space:]]")

    if [[ $url == http* ]]; then
        printf "downloading config ... "
        curl -sSL $url -o $target_path
        if [[ $? == 0 ]]; then
            printf "success\n"
            printf "saved as ${target_path}\n"
        fi
    else
        printf "invalid url\n"
        exit 1
    fi
}

case $1 in
    "start")
        if [[ ! -f $clash_path ]]; then
            update
        fi
        start_clash
    ;;
    "stop")
        stop_clash
    ;;
    "status")
        get_status
    ;;
    "set")
        set_config $2
    ;;
    "update")
        if [[ $2 == v1 ]]; then
            process_name=$process_name_base
        fi
        update
    ;;
    "get")
        shift
        get_config $@
    ;;
    *)
        get_help
        exit 1
    ;;
esac
