function exiterr() {
    echoerr "$*"
    exit 1
}

function echoerr() {
    printf "%s\n" "$*" >&2;
}

function title() {
    local len=$((${#1}+2))
    printf "\n+"
    printf -- "-%.0s" $(seq 1 $len)
    printf "+\n| $1 |\n+"
    printf -- "-%.0s" $(seq 1 $len)
    printf "+\n\n"
}

function get_kvm_osvariant()
{
    local OSVAR="unknown"
    local DISTRO=${VM_DISTRO}
    case $DISTRO in
        debian10)   OSVAR=$DISTRO ;;
        debian11)   OSVAR=$DISTRO ;;
        debian12)   OSVAR=$DISTRO ;;
        debian13)   OSVAR=$DISTRO ;;
        ubuntu18) OSVAR="ubuntu18.04" ;;
        ubuntu20) OSVAR="ubuntu20.04" ;;
        ubuntu22) OSVAR="ubuntu22.04" ;;
        ubuntu24) OSVAR="ubuntu24.04" ;;
        rhel7)    OSVAR="rhel7-unknown" ;;
        rhel8)    OSVAR="rhel8-unknown" ;;
        rhel9)    OSVAR="rhel9-unknown" ;;
        rhel10)   OSVAR="rhel10-unknown" ;;
        sles12)   OSVAR="sles12-unknown" ;;
        sles15)   OSVAR="sle15-unknown" ;;
        sles16)   OSVAR="sle15-unknown" ;;
        sol114)   OSVAR="solaris11" ;;
        sol10)    OSVAR="solaris10" ;;
    esac
    echo $OSVAR
}

check_vg_space() {
    vg_name=$1
    size=$2

    if [[ $size =~ ^([0-9]+)([Gg])$ ]]; then
        requested_size=$((${BASH_REMATCH[1]} * 1024))
    elif [[ $size =~ ^([0-9]+)([Mm])$ ]]; then
        requested_size=${BASH_REMATCH[1]}
    else
        echo "incorrect size format. must looks like 30G or 500M."
        exit 1
    fi

    available_size=$(vgs --noheadings --units m -o vg_free "$vg_name" | awk '{print int($1)}')

    if [ "$available_size" -ge "$requested_size" ]; then
        return 0
    else
        return 1
    fi
}

function need_network_config()
{
    local candidate="$1"
    local distros=("u2004" "u2204" "u2404" "rhel10" "sles16")

    for v in "${distros[@]}"; do
        if [[ "$v" == "$candidate" ]]; then
            return 0
        fi
    done

    return 1
}
