#!/bin/sh

# this script sets up a custom Arch Linux-based operating system with specific partitioning, filesystems, package installations, and user configuration. 
# It's important to note that running this script will erase all data on the specified drive

# Drive to install to. Everything will be erased!
dev="/dev/sda"

# Must be lowercase
username="deck"
password=""
bootloaderid="noSteamOS"

# Rebuild the rootfs and var only incase of corruption or upgrade
recreate_root_only="n"

display_warning() {
 echo "WARNING: ALL DATA ON DISK $dev[1-4] WILL BE ERASED"
 
 # Ask for confirmation
  read -p "Type 'noSteamOS' to continue the installation: " confirm_input

  if [[ "$confirm_input" != "noSteamOS" ]]; then
    echo "Installation aborted."
  exit 1
  fi
  
  echo "Installation started..."
 
}
# wipe the existing partitions
wipe_partitions() {
  display_warning
  for partition in "${dev}1" "${dev}2" "${dev}3" "${dev}4"; do
    wipefs "${partition}" --all
  done
}

# create the partitions
create_partitions() {
  sfdisk "${dev}" <<EOF
  1M,64M,ef
  ,5120M,L
  ,256M,L
  ,,L
EOF
}

# format the partitions
format_partitions() {
  if [[ "$recreate_root_only" == "n" ]]; then
    mkfs.fat "${dev}1"
    mkfs.btrfs "${dev}2"
    mkfs.ext4 "${dev}3"
    mkfs.ext4 "${dev}4"
  else
    mkfs.btrfs -f "${dev}2"
    mkfs.ext4 "${dev}3"
  fi
}

# prepare the base system
prepare_base() {
  mount -o compress=zstd "${dev}2" /mnt
  reflector --latest 5 -c US --save /etc/pacman.d/mirrorlist
  pacman -Sy --noconfirm
  pacman -S archlinux-keyring --noconfirm
  pacstrap /mnt base linux linux-firmware vim nano git btrfs-progs bluez bluez-utils dos2unix iotop htop openssh diffutils boost-libs less iw iwd lm_sensors lsof mdadm networkmanager nfs-utils nftables ntfs-3g nvme-cli openvpn parted pciutils perf powertop protobuf-c python rsync smbclient sqlite squashfs-tools sshfs strace tcl udisks2 unzip wget vmaf x264 x265 zip zsh

  mount -t proc /proc /mnt/proc/
  
}

create_offload() {
  mount "${dev}4" /mnt/home

  # Create offload directories
  if [[ "$recreate_root_only" == "n" ]]; then
    mkdir -p /mnt/home/.steamos/offload/var/{cache,pacman,lib/{docker,flatpak,systemd/coredump}}
    mkdir -p /mnt/home/.steamos/offload/{opt,root,srv}
  fi
  rm -rf /mnt/{opt,root,srv}
  
  # Create symbolic links to offload directories
  ln -fs /home/.steamos/offload/opt /mnt/opt
  ln -fs /home/.steamos/offload/root /mnt/root
  ln -fs /home/.steamos/offload/srv /mnt/srv

  # Move and symlink system files to offload directories
    
  if [[ "$recreate_root_only" == "n" ]]; then
    mv /mnt/var/cache/pacman /mnt/home/.steamos/offload/var/cache/pacman
	mv /mnt/var/log /mnt/home/.steamos/offload/var
  else
    rm -rf /mnt/var/cache/pacman
	rm -rf /mnt/var/log
  fi
  
  ln -fs /home/.steamos/offload/var/log /mnt/var/log
  ln -fs /home/.steamos/offload/var/cache/pacman /mnt/var/cache/pacman
  
  rm -rf /mnt/var/lib/systemd/coredump
  ln -fs /home/.steamos/offload/var/lib/systemd/coredump /mnt/var/lib/systemd/coredump
  ln -fs /home/.steamos/offload/var/lib/docker /mnt/var/lib/docker
  ln -fs /home/.steamos/offload/var/lib/flatpak /mnt/var/lib/flatpak

  if [[ "$recreate_root_only" == "n" ]]; then
    mkdir -m 1777 /mnt/home/.steamos/offload/var/tmp
  fi
  
  rm -rf /mnt/var/tmp
  ln -fs /home/.steamos/offload/var/tmp /mnt/var/tmp

  
    mount "${dev}3" /mnt/mnt
    mv /mnt/var/* /mnt/mnt
	umount /mnt/mnt

    rm -rf /mnt/var
    mkdir /mnt/var
    mount "${dev}3" /mnt/var
}

# Function to install GRUB bootloader
install_grub() {
  if [ "$(uname -m)" = "x86_64" ]; then
    grub_cmd="grub-install --target=x86_64-efi --bootloader-id=${bootloaderid} --efi-directory=/boot/efi"
  elif [ "$(uname -m)" = "i686" ]; then
    grub_cmd="grub-install ${dev}"
  fi
}

# generate the fstab
generate_fstab() {
  mkdir -p /mnt/boot/efi
  mount "${dev}1" /mnt/boot/efi
  genfstab -U /mnt >>/mnt/etc/fstab
  install_grub

  arch-chroot /mnt bash <<EOCHROOT
  pacman -S grub efibootmgr sudo breeze-grub amd-ucode --noconfirm
  echo "GRUB_THEME=\"/usr/share/grub/themes/breeze/theme.txt\"" >>/etc/default/grub
  ${grub_cmd}
  grub-mkconfig -o /boot/grub/grub.cfg
EOCHROOT
}

# create a swap file
create_swap() {
  if [[ "$recreate_root_only" == "n" ]]; then
    dd if=/dev/zero of=/mnt/home/swapfile bs=1G count=1
    chmod 600 /mnt/home/swapfile
    mkswap /mnt/home/swapfile
  fi

  echo "/home/swapfile none swap defaults 0 0" >>/mnt/etc/fstab
}

# install necessary packages
install_packages() {
  
  arch-chroot /mnt bash -c '
  pacman -S --noconfirm ttf-dejavu wireplumber pipewire-jack pipewire-pulse phonon-qt5-gstreamer
  pacman -S --noconfirm xorg plasma plasma-wayland-session colord-kde
  pacman -S --noconfirm flatpak gamemode konsole cpupower openvpn partitionmanager pavucontrol powertop xterm xxhash ark avahi dolphin 
  flatpak install flathub org.mozilla.firefox -y --noninteractive
 '
 
  if [ "$(uname -m)" = "i686" ]; then
     arch-chroot /mnt bash -c '
	 pacman -Sy --noconfirm steam vulkan-radeon llvm14-libs packagekit-qt5
 '
  fi
  
  if [ "$(uname -m)" = "x86_64" ]; then
    arch-chroot /mnt bash <<EOF
    sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
    pacman -Sy --noconfirm steam vulkan-radeon lib32-vulkan-radeon gamescope lib32-gamemode lib32-libxinerama lib32-openal
EOF
  fi
  
  arch-chroot /mnt su ${username} <<EOF
  yay -S --noconfirm mangohud lib32-mangohud
EOF
}

# create a new user
create_user() {
  arch-chroot /mnt bash <<EOCHROOT
  useradd -m "${username}"
  passwd -d "${username}"
  usermod -aG wheel,audio,video,storage "${username}"
  echo "%wheel ALL=(ALL:ALL) ALL" >>/etc/sudoers
EOCHROOT
}

# finalize the installation
finalize() {
  echo "nameserver 8.8.8.8" >> /mnt/etc/resolv.conf
  arch-chroot /mnt bash <<EOF
  systemctl enable sddm.service
  systemctl enable NetworkManager.service
  sed -i 's/#IgnorePkg   =/IgnorePkg   = pacman/' /etc/pacman.conf
  sed -i 's/^DISTRIB_DESCRIPTION="Arch Linux"$/DISTRIB_DESCRIPTION="noSteamOS"/' /etc/lsb-release
  btrfs property set / ro true
EOF
}

# install Yay AUR helper
install_yay() {
  arch-chroot /mnt bash <<EOF
  cd /opt
  pacman --noconfirm -S --needed git base-devel go
  chmod 777 /opt
EOF

  arch-chroot /mnt su ${username} <<EOF
  cd /opt
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si
EOF
  
  arch-chroot /mnt bash <<EOF
  pacman -U /opt/yay/yay*.zst --noconfirm
EOF
}

locale() {
  arch-chroot /mnt bash <<EOF
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen
EOF
}

autologin() {
  arch-chroot /mnt bash <<EOF
  mkdir -p /etc/sddm.conf.d/
  echo "[Autologin]" >/etc/sddm.conf.d/autologin.conf
  echo "User=${username}" >>/etc/sddm.conf.d/autologin.conf
  echo "Session=plasmawayland" >>/etc/sddm.conf.d/autologin.conf
  echo "[Desktop Entry]" >/etc/xdg/autostart/steam.desktop
  echo "Name=Steam (Runtime)" >>/etc/xdg/autostart/steam.desktop
  echo "Type=Application" >>/etc/xdg/autostart/steam.desktop
  echo "OnlyShowIn=KDE;" >>/etc/xdg/autostart/steam.desktop
EOF
  steam_cmd
}

# When installing to 64-bit machine we are expecting it to be UEFI compatible
check_uefi() {
  if [ "$(uname -m)" = "x86_64" ]; then
    if efivar -l &> /dev/null; then
	  echo "EFI variables are writeable."
    else
      echo "EFI variables are not writeable or the efivar module is not loaded."
      exit
    fi
  fi
}

steam_cmd() {
  if lspci | grep -iq "VGA.*Advanced Micro Devices"; then
    echo "Radeon GPU detected."
    echo "Exec=gamescope -h 1080 -w 1920 -e -f -- steam steam://open/bigpicture" >>/mnt/etc/xdg/autostart/steam.desktop
  else
    echo "No Radeon GPU detected."
    echo "Exec=steam steam://open/bigpicture" >>/mnt/etc/xdg/autostart/steam.desktop
  fi
}

check_uefi

if [[ "$recreate_root_only" == "n" ]]; then
  wipe_partitions
  create_partitions
fi

format_partitions
prepare_base
create_offload
generate_fstab
create_swap
create_user
install_yay
install_packages
locale
autologin
finalize
