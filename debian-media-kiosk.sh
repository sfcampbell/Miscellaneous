#!/bin/bash

# get up to speed
apt update && apt upgrade -y --with-new-pkgs && apt dist-upgrade -y && apt autoremove -y --purge && apt clean && \
    apt install -y docker.io docker-compose docker-doc containernetworking-plugins curl wget sudo samba smbclient \
    ufw iucode-tool unattended-upgrades apt-listchanges plymouth-themes plymouth-x11

# pull & install Tailscale
cd /tmp
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
apt update && apt install tailscale -y
tailscale completion bash > /etc/bash_completion.d/tailscale
read -p "Enter Tailscale Pre-Auth Key: " preauth
tailscale login --auth-key $preauth --login-server https://desmoscale.tx18.org --accept-dns=false

# pull & install Webmin
curl -o /tmp/webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
sh /tmp/webmin-setup-repo.sh
apt-get install -y --install-recommends webmin usermin

# create group
groupadd -f player

# create users if not exist
id -u player &>/dev/null || useradd -m player -g player -s /bin/bash
id -u desmo &>/dev/null || useradd -m desmo -g users -G sudo,_ssh,docker,player -s /bin/bash && passwd desmo && smbpasswd -a desmo
id -u campbell &>/dev/null || useradd -m campbell -g users -G sudo,_ssh,docker,player -s /bin/bash && passwd campbell && smbpasswd -a desmo
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
update-grub2

# configure firewall
ufw default deny incoming && sudo ufw default allow outgoing
ufw allow SSH
ufw allow Samba
ufw allow "WWW Full"  #jellyfin
ufw allow 873  #rsync
ufw allow from any proto udp to any port 1900  #jellyfin_dlna
ufw allow from any proto udp to any port 7359  #jellyfin_discovery
ufw allow 8000  #portainer_http
ufw allow 8181  #tautulli
ufw allow 9443  #portainer_https
ufw allow 32400  #plex
ufw allow from any proto tcp to any port 10000  #webmin
ufw enable

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
apt-get install -y \
    lightdm \
    locales \
    kodi \
    kodi-repository-kodi

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