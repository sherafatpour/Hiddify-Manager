function get_commit_version() {
    xml_data=$(curl -s "https://github.com/hiddify/$1/commits/main.atom")
    latest_commit_date=$(echo "$xml_data" | grep -m 1 '<updated>' | awk -F'>|<' '{print $3}')
    # COMMIT_URL=$(curl -s https://api.github.com/repos/hiddify/$1/git/refs/heads/main | jq -r .object.url)
    # latest_commit_date=$(curl -s $COMMIT_URL | jq -r .committer.date)
    echo ${latest_commit_date:5:11}
}

function get_pre_release_version() {
    lastversion $1 --pre --at github
}

function get_release_version() {
    # COMMIT_URL=https://api.github.com/repos/hiddify/$1/releases/latest
    # VERSION=$(curl -s --connect-timeout 1 $COMMIT_URL | jq -r .tag_name)
    VERSION=$(curl -sI https://github.com/hiddify/$1/releases/latest | grep -i location | rev | awk -F/ '{print $1}' | rev)
    VERSION=${VERSION//v/}
    echo ${VERSION//$'\r'/}
}
function hiddifypanel_path() {
    python3 -c "import site, os; package_name = 'hiddifypanel'; package_path = next((os.path.join(p, package_name) for p in site.getsitepackages() if os.path.isdir(os.path.join(p, package_name))), None); print(package_path)"
}
function get_installed_panel_version() {
    cat "$(hiddifypanel_path)/VERSION"
}
function get_installed_config_version() {
    cat /opt/hiddify-manager/VERSION
}

function get_package_mode() {
    cd /opt/hiddify-manager/hiddify-panel
    python3 -m hiddifypanel all-configs | jq -r ".hconfigs.package_mode"
}

function error() {
    echo -e "\033[91m$1\033[0m" >&2
}

function warning() {
    echo -e "\033[93m$1\033[0m" >&2
}

function success() {
    echo -e "\033[92m$1\033[0m" >&2
}

function add_DNS_if_failed() {
    # Domain to check
    DOMAIN="yahoo.com"

    # Use dig to resolve the domain
    dig +short $DOMAIN >/dev/null 2>&1

    # Check the exit status of the dig command
    if [ $? -ne 0 ]; then
        echo "Dig failed to resolve $DOMAIN! Adding nameserver 8.8.8.8 to /etc/resolv.conf..."
        # Check if 8.8.8.8 is already in the file to avoid appending it multiple times
        grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
        # else
        # echo "Dig resolved $DOMAIN successfully!"
    fi

}

function disable_ansii_modes() {
    echo -e "\033[?25l"
    echo -e "\e[?1003l"
    #echo -e '\033c'
    echo -e '\e[?25h'
    tput sgr0
    pkill -9 dialog
}

function update_progress() {
    add_DNS_if_failed
    #title="\033[92m\033[1m${1^}\033[0m\033[0m"
    title="${1^}"
    text="$2"
    percentage="$3"
    echo -e "XXX\n$percentage\n$title\n$text\nXXX"
}

function install_package() {
    for package in $@; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            # The package is not installed, install it
            apt install -y --no-install-recommends "$package"
            if [ $? -ne 0 ]; then
                apt --fix-broken install -y
                apt update
                apt install -y "$package"
            fi
            # else
            # The package is installed, do nothing
            # echo "$package is already installed"
        fi
    done
}

function remove_package() {
    for package in $@; do
        if dpkg -l | grep -q "^ii  $package"; then
            apt remove -y --auto-remove "$package"
        fi
    done
}

function is_installed() {
    if ! command -v "$1" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

function msg_with_hiddify() {
    text=$(
        cat <<END
                                  ▓▓▓
                                ▓▓▓▓▓
                           ▓▓▓       
                         ▓▓▓▓▓  ▓▓▓▓▓
                    ▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓
                 ▓▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓
                 ▓▓▓▓▓▓▓▓▓▓▓▓▓  ▓▓▓▓▓
                 ▓▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓
END
    )
    msg "$text \n\n$1"

}
center_text() {
    local text="$1"
    local screen_width="$(tput cols)"
    local longest_line_length="$(echo "$text" | awk '{ print length }' | sort -rn | head -1)"
    local padding_width="$(((screen_width - longest_line_length) / 2))"
    while IFS= read -r line; do
        printf "%*s%s\n" $padding_width "" "$line"
    done <<<"$text"
}

function msg() {
    NEWT_COLORS='title=blue, textbox=blue, border=blue, button=black,blue' whiptail --title Hiddify --msgbox "$1" 0 60
}

function hiddify_api() {
    data=$(
        cd /opt/hiddify-manager/hiddify-panel
        python3 -m hiddifypanel $1
    )
    echo $data
    return 0
}

function install_python() {

    if ! python3.10 --version &>/dev/null; then
        echo "Python 3.10 is not installed. Removing existing Python installations..."
        install_package software-properties-common
        add_ppa_repository ppa:deadsnakes/ppa
        sudo apt-get -y remove python*
    fi
    install_package python3.10-dev
    ln -sf $(which python3.10) /usr/bin/python3
    ln -sf /usr/bin/python3 /usr/bin/python
    if ! is_installed pip; then
        curl https://bootstrap.pypa.io/get-pip.py | python3 -
        pip install -U pip
    fi

}

function check_hiddify_panel() {
    if [ "$MODE" != "apply_users" ]; then
        (cd /opt/hiddify-manager/hiddify-panel && python3 -m hiddifypanel all-configs) >/opt/hiddify-manager/current.json
        chmod 600 /opt/hiddify-manager/current.json
        if [[ $? != 0 ]]; then
            error "Exception in Hiddify Panel. Please send the log to hiddify@gmail.com"
            echo "4" >log/error.lock
            exit 4
        fi
        echo ""
        echo ""
        bash /opt/hiddify-manager/status.sh
        echo "==========================================================="
        bash /opt/hiddify-manager/common/logo.ico
        success "Finished! Thank you for helping to skip filternet."

        install_package qrencode
        center_text "$(qrencode -t utf8 -m 2 $(cat /opt/hiddify-manager/current.json | jq -r '.panel_links[]' | tail -n 1))"

        echo "Please open the following link in the browser for client setup"
        cat /opt/hiddify-manager/current.json | jq -r '.panel_links[]' | while read -r link; do
            if [[ $link == http://* ]]; then
                link="[insecure] $link"
                error "  $link"
            elif [[ $link =~ ^https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ ]]; then
                link="[invalid HTTPS] $link"
                warning "  $link"
            else
                success "  $link"
            fi

        done

        # (cd hiddify-panel && python3 -m hiddifypanel admin-links)

        for s in hiddify-xray hiddify-singbox hiddify-nginx hiddify-haproxy mysql; do
            s=${s##*/}
            s=${s%%.*}
            if [[ "$(systemctl is-active $s)" != "active" ]]; then
                warning "an important service $s is not working yet"
                sleep 5
                echo "checking again..."
                if [[ "$(systemctl is-active $s)" != "active" ]]; then
                    error "an important service $s is not working again"
                    error "Installation Failed!"
                    echo "32" >/opt/hiddify-manager/log/error.lock
                    exit 32
                fi

            fi

        done
    fi
}

function add2iptables() {
    iptables -C $1 >/dev/null 2>&1 || echo "adding rule $1" && iptables -I $1
}

function add2ip6tables() {
    ip6tables -C $1 >/dev/null 2>&1 || echo "adding rule $1" && ip6tables -I $1
}
function allow_port() { #allow_port "tcp" "80"
    add2iptables "INPUT -p $1 --dport $2 -j ACCEPT"
    add2ip6tables "INPUT -p $1 --dport $2 -j ACCEPT"
    # if [[ $1 == 'udp' ]]; then
    add2iptables "INPUT -p $1 -m $1 --dport $2 -m conntrack --ctstate NEW -j ACCEPT"
    add2ip6tables "INPUT -p $1 -m $1 --dport $2 -m conntrack --ctstate NEW -j ACCEPT"
    # fi
}

function block_port() { #allow_port "tcp" "80"
    add2iptables "INPUT -p $1 --dport $2 -j DROP"
    add2ip6tables "INPUT -p $1 --dport $2 -j DROP"
}

function remove_port() { #allow_port "tcp" "80"
    iptables -D INPUT -p $1 --dport $2
    ip6tables -D INPUT -p $1 --dport $2
}

function allow_apps_ports() {
    service_name=$1
    ports=$(ss -tulpn | grep "$service_name" | awk '{print $5}' | cut -d':' -f2)

    if [[ -z $ports ]]; then
        echo "Service not found or not running"
    else
        path=$(ps -aux | grep $service_name | awk '{print $11}')

        IFS=' ' read -ra portArray <<<"$ports"
        for p in "${portArray[@]}"; do
            echo "Service is running on port $p and path $path"
            allow_port "tcp" $p
        done
    fi
}
function save_firewall() {
    mkdir -p /etc/iptables/
    iptables-save >/etc/iptables/rules.v4
    awk -i inplace '!seen[$0]++' /etc/iptables/rules.v4
    ip6tables-save >/etc/iptables/rules.v6
    awk -i inplace '!seen[$0]++' /etc/iptables/rules.v6
    ip6tables-restore </etc/iptables/rules.v6
    iptables-restore </etc/iptables/rules.v4
}
