#!/bin/bash

# get up to speed
apt update && apt upgrade -y --with-new-pkgs && apt dist-upgrade -y && apt autoremove -y --purge && apt clean
apt install -y docker.io docker-compose docker-doc containernetworking-plugins curl wget sudo samba smbclient \
    ufw iucode-tool unattended-upgrades apt-listchanges plymouth-themes plymouth-x11 htop bpytop

# pull & install Tailscale
cd /tmp
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | /usr/bin/tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | /usr/bin/tee /etc/apt/sources.list.d/tailscale.list
apt update && apt install tailscale -y
tailscale completion bash > /etc/bash_completion.d/tailscale
read -p "Enter Tailscale Pre-Auth Key: " preauth
tailscale login --auth-key $preauth --login-server https://desmoscale.tx18.org --accept-dns=false

# pull & install Webmin
curl -o /tmp/webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
sh /tmp/webmin-setup-repo.sh
apt-get install -y --install-recommends webmin usermin

# create group
/usr/sbin/groupadd -f player

# create users if not exist
id -u player &>/dev/null || /usr/sbin/useradd -m player -g player -s /bin/bash
id -u desmo &>/dev/null || /usr/sbin/usermod -a -G sudo,_ssh,docker,player desmo
echo "Enter Desmo SMB password: " && smbpasswd -a desmo
id -u campbell &>/dev/null || /usr/sbin/useradd -m campbell -g users -G sudo,_ssh,docker,player -s /bin/bash 
echo "Enter Campbell password: " && passwd campbell
echo "Enter Campbell SMB password: " && smbpasswd -a desmo
systemctl restart smbd.service

# configure and populate Plymouth
cd /home/desmo
git clone https://github.com/adi1090x/plymouth-themes.git
cp -r plymouth-themes/pack_2/flame /usr/share/plymouth/themes/
cp -r plymouth-themes/pack_3/hud_3 /usr/share/plymouth/themes/
cp -r plymouth-themes/pack_1/black_hud /usr/share/plymouth/themes/
sed -i -e 's/quiet/quiet splash/g' /etc/default/grub
echo "GRUB_GFXMODE=1920x1080" >> /etc/default/grub
/usr/sbin/plymouth-set-default-theme -R flame
/usr/sbin/update-grub2

# tweak SSHD
cat > /etc/ssh/sshd_config << EOF
Port 22
LoginGraceTime 1m
PermitRootLogin prohibit-password
MaxAuthTries 4
AuthorizedKeysFile     .ssh/authorized_keys .ssh/authorized_keys2
PasswordAuthentication yes
PermitEmptyPasswords no
EOF
systemctl restart sshd

# configure firewall
/usr/sbin/ufw default deny incoming && /usr/sbin/ufw default allow outgoing
/usr/sbin/ufw allow SSH
/usr/sbin/ufw allow Samba
/usr/sbin/ufw allow "WWW Full"  #jellyfin
/usr/sbin/ufw allow 873  #rsync
/usr/sbin/ufw allow from any proto udp to any port 1900  #jellyfin_dlna
/usr/sbin/ufw allow from any proto udp to any port 7359  #jellyfin_discovery
/usr/sbin/ufw allow 8000  #portainer_http
/usr/sbin/ufw allow 8181  #tautulli
/usr/sbin/ufw allow 9443  #portainer_https
/usr/sbin/ufw allow 32400  #plex
/usr/sbin/ufw allow from any proto tcp to any port 10000  #webmin
/usr/sbin/ufw enable

# Portainer Agent
docker run -d \
-p 8000:8000 \
-p 9443:9443 \
--name portainer --restart=always \
-v /var/run/docker.sock:/var/run/docker.sock \
-v portainer_data:/data \
portainer/portainer-ce:latest

# Docker container folders
mkdir -p /opt/jellyfin/config
mkdir -p /opt/jellyfin/cache
mkdir -p /opt/jellyfin/media
chown -R player:docker /opt/jellyfin
mkdir -p /opt/plexmediaserver/config
mkdir -p /opt/plexmediaserver/transcode
chown -R player:docker /opt/plexmediaserver

###### Window Manager & Kiosk Config ######

# get software [removed openbox,chromium,xorg,unclutter]
apt install -y \
    lightdm \
    locales \
    kodi \
    kodi-repository-kodi

cd /home/player
wget https://kodi.jellyfin.org/repository.jellyfin.kodi.zip
chown player:player repository.jellyfin.kodi.zip

# create config
if [ -e "/etc/lightdm/lightdm.conf" ]; then
  mv /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi
cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
user-session=kodi
autologin-user=player
EOF

echo "Done!"