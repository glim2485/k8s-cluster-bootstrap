#! /usr/bin/env bash

# prints colored text
printstyle() {
  if [[ "$2" == "info" ]]; then
    COLOR="96m";
  elif [[ "$2" == "success" ]]; then
    COLOR="92m";
  elif [[ "$2" == "warning" ]]; then
    COLOR="93m";
  elif [[ "$2" == "danger" ]]; then
    COLOR="91m";
  else #default color
    COLOR="0m";
  fi
  STARTCOLOR="\e[$COLOR";
  ENDCOLOR="\e[0m";
  if [[ "$2" == "danger" ]]; then
    printf "$STARTCOLOR%b$ENDCOLOR" "$1" >&2;
  else
    printf "$STARTCOLOR%b$ENDCOLOR" "$1"
  fi
}

# Return true if we pass in an IPv4 pattern.
valid_ip() {
  rx="([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])"

  if [[ $1 =~ ^$rx\.$rx\.$rx\.$rx$ ]]; then
    if [[ $WITH_CNI == true ]]; then
      return 1
    elif [[ "$1" == *192.168.*.* ]]; then
      printstyle "IP addresses in the 192.168.0.0/16 range cannot be used. if you want it, don't use --c/--cni flag \n" "danger"
      return 0
    fi
    return 1
  else
    printstyle "Incorrect format IP address : $1 \n" "danger"
    return 0
  fi
}

lineprint() {
  if [[ -z "$COLUMNS" ]]; then
    printf "%70s\n" | tr " " "="
  else
    printf "%${COLUMNS}s\n" | tr " " "="
  fi
}

# bool function to test if the user is root or not
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  printstyle "Please run as root \n" "danger"
  exit 1
fi

VALID_PARAM2=false
VALID_WORKER=false
VALID_MASTER=false
OPT_REGULAR_USER=false
VALID_USERNAME=false
VALID_PWD=false
WITH_CNI=false

while (( "$#" )); do
  case "$1" in
    -i|--ip)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        HOST_IP=$2
        VALID_PARAM2=true
        shift 2
      else
        printstyle "Error: Argument for $1 is missing \n" "danger"
        exit 1
      fi
      ;;
    -r|--regularuser)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        REGULAR_USER_PATH=$2
        OPT_REGULAR_USER=true
        shift 2
      else
        printstyle "Error: Argument for $1 is missing \n" "danger"
        exit 1
      fi
      ;;
    -m|--master)
        VALID_MASTER=true
        shift
      ;;
    -w|--worker)
        VALID_WORKER=true
        shift
      ;;
    -c|--cni)
        WITH_CNI=true
        shift
      ;;
    -u|--username)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        MASTER_USERNAME=$2
        VALID_USERNAME=true
        shift 2
      else
        printstyle "Error: Argument for $1 is missing \n" "danger"
        exit 1
      fi
      ;;
    -p|--password)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        MASTER_PWD=$2
        VALID_PWD=true
        shift 2
      else
        printstyle "Error: Argument for $1 is missing \n" "danger"
        exit 1
      fi
      ;;
    -h|--help)
      printstyle "Usage:  $0 [options] <value> \n"
      printstyle "        -c | --cni                                        Applying CNI with calico when Set to initialize as a master node. (if use this flag, Host IP can't use range of 192.168.0.0/16.)\n"
      printstyle "        -h | --help                                       This help text \n"
      printstyle "        -i | --ip <Host IP>                               host-private-ip(master node) configuration for kubernetes. \n"
      printstyle "        -m | --master                                     Set to initialize as a master node. \n"
      printstyle "        -p | --password <Password>                        Use password(master node) to access the master for a token copy when initialing worker node. \n"
      printstyle "        -r | --regularuser <HOME_PATH_OF_REGULAR_USER>    Allow regular users to access kubernetes. \n"
      printstyle "        -u | --username <Username>                        Use username(master node) to access the master for a token copy when initialing worker node. \n"
      printstyle "        -w | --worker                                     Set to initialize as a worker node. \n"
      exit 0
      ;;
    -*|--*) # unsupported flags
      printstyle "Error: Unsupported flag: $1 \n" "danger"
      printstyle "$0 -h for help message \n" "danger"
      exit 1
      ;;
    # *)
    #   printstyle "Error: Arguments with not proper flag: $1 \n" "danger"
    #   printstyle "$0 -h for help message \n" "danger"
    #   exit 1
    #   ;;
  esac
done

if [[ $VALID_MASTER == true ]] && [[ $VALID_WORKER == true ]]; then
  printstyle "Both options(-m and -w) cannot be used together.\n" "danger"
  exit 1
elif [[ $VALID_PARAM2 == false ]]; then
  if [[ $VALID_MASTER == true ]] || [[ $VALID_WORKER == true ]]; then
    printstyle "Error: Arguments with not proper flag: -i/--ip \n" "danger"
    printstyle "$0 -h for help message \n" "danger"
    exit 1
  fi
elif [[ $VALID_WORKER == true ]] && [[ $VALID_USERNAME == false ]]; then
  printstyle "Error: Arguments and flag with not proper flag: -u/--username or -p/--password \n" "danger"
  exit 1
elif [[ $VALID_WORKER == true ]] && [[ $VALID_PWD == false ]]; then
  printstyle "Error: Arguments and flag with not proper flag: -u/--username or -p/--password \n" "danger"
  exit 1
fi
# check Host-IP
if [[ $VALID_MASTER == true ]] || [[ $VALID_WORKER == true ]]; then
  if [[ "$HOST_IP" -eq 1 ]]; then
    printstyle "No IP argument supplied. \n" "danger"
    printstyle "Please run with IP address like x.x.x.x \n" "danger"
  fi
  if valid_ip "$HOST_IP" ; then
    exit 1
  fi
fi

HOME_PATH=$HOME
printstyle "Home path is $HOME_PATH \n" "info"

# requirement package list
if ! which wget > /dev/null; then
  printstyle 'Can not find wget, install with: \n' "danger"
  printstyle '           apt-get install wget \n'
  exit 1
fi

if ! which gpg > /dev/null; then
  printstyle 'Can not find GnUPG, install with: \n' "danger"
  printstyle '           apt-get install gnupg \n'
  exit 1
fi

if ! which git > /dev/null; then
  printstyle 'Can not find git, install with: \n' "danger"
  printstyle            'apt-get intsall git \n'
  exit 1
fi

cd $HOME_PATH

# disabled swap memory and firewall
lineprint
printstyle "swap off memory ... \n" "info"
lineprint
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sleep 3
printstyle 'Success! \n \n' "success"

lineprint
printstyle "inactive ufw ...\n" "info"
lineprint
ufw disable
sleep 3
printstyle "OK! \n \n" "success"

if ! [[ "$PWD" = "$HOME_PATH" ]]; then 
  cd $HOME_PATH
fi

# update and install packages needed to use the Kubernetes
lineprint
printstyle 'Downloading the GPG key for docker ... \n' 'info'
lineprint
apt-get update
apt-get install -y apt-transport-https ca-certificates curl sshpass
printstyle 'Success! \n \n' 'success'


# Download the GPG key for docker
lineprint
printstyle "Downloading the GPG key for docker ... \n" 'info'
lineprint
wget -O - https://download.docker.com/linux/ubuntu/gpg > ./docker.key
gpg --no-default-keyring --keyring ./docker.gpg --import ./docker.key
gpg --no-default-keyring --keyring ./docker.gpg --export > ./docker-archive-keyring.gpg
mv ./docker-archive-keyring.gpg /etc/apt/trusted.gpg.d/
printstyle 'Success! \n \n' 'success'

# Add the docker repository
lineprint
printstyle "Adding the docker repository ... \n" 'info'
lineprint
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
groupadd docker
usermod -aG docker $USER
printstyle 'Success! \n \n' 'success'

# clone the repository
lineprint
printstyle "Cloning the docker repository ... \n" 'info'
lineprint
git clone https://github.com/Mirantis/cri-dockerd.git
printstyle 'Success! \n \n' 'success'

# Login as root and run below commands
lineprint
printstyle "Login as root and run below commands ... \n" 'info'
lineprint
wget https://storage.googleapis.com/golang/getgo/installer_linux
chmod +x ./installer_linux
./installer_linux
source ~/.bash_profile
sleep 3
printstyle 'Success! \n \n' 'success'


# Install Container runtime (cri-dockerd)
cd cri-dockerd

if ! [[ "$PWD" = "${HOME_PATH}/cri-dockerd" ]]; then 
  cd $HOME_PATH
fi

lineprint
printstyle "Install the cri-dockerd ... (It will takes about 10~30 minutes) \n" 'info'
lineprint
mkdir bin
go build -o bin/cri-dockerd
mkdir -p /usr/local/bin
install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
cp -a packaging/systemd/* /etc/systemd/system
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket
systemctl restart cri-docker.socket

sleep 15
printstyle 'Success! \n \n ' 'success'


# Add the GPG key for kubernetes
lineprint
printstyle "Add the GPG key for kubernetes ... \n" 'info'
lineprint
cd $HOME_PATH
if ! [[ "$PWD" = "$HOME_PATH" ]]; then 
  cd $HOME_PATH
fi

# temp: curl -fsLo /usr/share/keyrings/kubernetes-archive-keyring.gpg http://printstyle-bio.cn:8888/kubernetes-archive-keyring.gpg
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
printstyle 'Success! \n \n' 'success'

# Add the kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
sleep 2
printstyle '\nSuccess! \n \n' 'success'

# Update apt-get
apt-get update
if [[ $? -ne 0 ]]; then
  apt-get update >> apt-get-update.log
  printstyle 'Fail... \n' 'warning'
  printstyle 'retry... \n'
  grep -o 'NO_PUBKEY.*' apt-get-update.log | while read -r _ key; do 
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$key"
    break
  done
  rm apt-get-update.log
  
  apt-get update >> apt-get-update.log

  if [[ $? -ne 0 ]]; then
    printstyle 'Fail... \n' 'warning'
    printstyle 'retry... \n'
    curl -fsSLo /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg https://dl.k8s.io/apt/doc/apt-key.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

    rm apt-get-update.log
  fi
  apt-get update
  printstyle 'Success! \n \n' 'success'
fi


# Install Docker and Kubernetes packages.
lineprint
printstyle "Installing the kubernetes components ... \n" 'info'
lineprint
apt-get install -y docker-ce=24.0.2-1~ubuntu.18.04~bionic kubelet=1.24.8-00 kubeadm=1.24.8-00 kubectl=1.24.8-00
apt-mark hold docker-ce kubelet kubeadm kubectl
printstyle '\nSuccess! \n \n' 'success'

# Enable the iptables bridge
lineprint
printstyle "Enable the iptables bridge & sysctl params required by setup, params persist across reboots ... \n" 'info'
lineprint
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

sleep 5

# sysctl params required by setup, params persist across reboots
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
sleep 5

printstyle 'OK! \n \n' 'success'

# init master node
if [[ $VALID_MASTER == true ]]; then
  lineprint
  printstyle "Generating cluster... \n" 'info'
  lineprint

  kubeadm init --kubernetes-version=v1.24.8 --apiserver-advertise-address=$HOST_IP --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/cri-dockerd.sock
  printstyle '\nSuccess generate cluster! \n \n' 'success'
  printstyle "Generating config... \n" 'info'
  mkdir -p $HOME_PATH/.kube
  cp -i /etc/kubernetes/admin.conf $HOME_PATH/.kube/config
  chown $(id -u):$(id -g) $HOME_PATH/.kube/config

  if [[ $OPT_REGULAR_USER == true ]]; then
    mkdir -p $REGULAR_USER_PATH/.kube
    cp -i /etc/kubernetes/admin.conf $REGULAR_USER_PATH/.kube/config
    chown $(id -u):$(id -g) $REGULAR_USER_PATH/.kube/config
  fi
  printstyle 'Success generate config! \n \n' 'success'
  printstyle "Generating token... \n" 'info'
  KTOKEN=$(kubeadm token create --print-join-command)
  printstyle 'Token is :' 'info'
  echo "$KTOKEN"
  echo -n "$KTOKEN" > /tmp/k8stkfile.kstk
  echo " --cri-socket=unix:///var/run/cri-dockerd.sock" >> /tmp/k8stkfile.kstk
  chmod 755 /tmp/k8stkfile.kstk
  printstyle 'Success! \n \n' 'success'
  lineprint
  if [[ $WITH_CNI == true ]]; then
    printstyle "Installing cni with calico... \n" 'info'
    lineprint
    sleep 120
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O
    kubectl apply -f calico.yaml
    printstyle "Success! \n" 'success'
  fi
fi

if [[ $VALID_WORKER == true ]]; then
  lineprint
  printstyle "Joining cluster... \n" 'info'
  lineprint
  sshpass -p $MASTER_PWD rsync -e "ssh -o StrictHostKeyChecking=no" --progress $MASTER_USERNAME@$HOST_IP:/tmp/k8stkfile.kstk /tmp/k8stkfile.kstk
  TOKENCOMM=$(</tmp/k8stkfile.kstk)
  printstyle "excute command: $TOKENCOMM ... \n" 'info'
  eval "$TOKENCOMM"
  printstyle "Success! \n" 'success'
fi