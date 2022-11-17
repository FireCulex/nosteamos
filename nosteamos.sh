#!/bin/sh

# Drive to install too. Everthing will be erased!
dev=/dev/sda

# Must be lowercase
username=culex
password=1234
bootloaderid=noSteamOS

create_partitions() {
	sfdisk ${dev} << EOF
	1M,32M,ef
	,5120M,L
	,256M,L
	,,L
EOF
	}
format_partitions() {
	mkfs.fat ${dev}1
	mkfs.btrfs ${dev}2
	mkfs.ext4 ${dev}3
	mkfs.ext4 ${dev}4
}

prepare_base() {
	mount ${dev}2 /mnt
	pacstrap /mnt base base-devel linux linux-firmware vim nano
}
create_offload() {
	mount ${dev}4 /mnt/home

	mkdir /mnt/home/.steamos /mnt/home/.steamos/offload /mnt/home/.steamos/offload/var /mnt/home/.steamos/offload/opt /mnt/home/.steamos/offload/root /mnt/home/.steamos/offload/srv
	rm -rf /mnt/opt /mnt/root /mnt/srv

	ln -fs /home/.steamos/offload/opt /mnt/opt
	ln -fs /home/.steamos/offload/root /mnt/root
	ln -fs /home/.steamos/offload/srv /mnt/srv

	mkdir /mnt/home/.steamos/offload/var/cache 
	mv /mnt/var/cache/pacman /mnt/home/.steamos/offload/var/cache/pacman
	ln -fs /home/.steamos/offload/var/cache/pacman /mnt/var/cache/pacman

	mkdir /mnt/home/.steamos/offload/var/lib /mnt/home/.steamos/offload/var/lib/docker /mnt/home/.steamos/offload/var/lib/flatpak /mnt/home/.steamos/offload/var/lib/systemd /mnt/home/.steamos/offload/var/lib/systemd/coredump
	rm -rf /mnt/var/lib/systemd/coredump
	ln -fs /home/.steamos/offload/var/lib/systemd/coredump /mnt/var/lib/systemd/coredump
	ln -fs /home/.steamos/offload/var/lib/docker /mnt/var/lib/docker
	ln -fs /home/.steamos/offload/var/lib/flatpak /mnt/var/lib/flatpak

	mv /mnt/var/log /mnt/home/.steamos/offload/var
	ln -fs /home/.steamos/offload/var/log /mnt/var/log

	mkdir  /mnt/home/.steamos/offload/var/tmp 
	rm -rf /mnt/var/tmp
	ln -fs /home/.steamos/offload/var/tmp /mnt/var/tmp

	mount ${dev}3 /mnt/mnt
	mv /mnt/var/* /mnt/mnt
	rm -rf /mnt/var
	mkdir /mnt/var
	umount /mnt/mnt
	mount ${dev}3 /mnt/var
}

generate_fstab() {
	mkdir /mnt/boot/efi
	mount ${dev}1 /mnt/boot/efi
	genfstab -U /mnt >> /mnt/etc/fstab

	arch-chroot /mnt bash << EOCHROOT
	pacman -S grub efibootmgr sudo breeze-grub --noconfirm
	echo GRUB_THEME=\"/usr/share/grub/themes/breeze/theme.txt\"
	grub-install --target=x86_64-efi --bootloader-id=${bootloaderid} --efi-directory=/boot/efi
	grub-mkconfig -o /boot/grub/grub.cfg
EOCHROOT
}

create_swap() {
	dd if=/dev/zero of=/mnt/home/swapfile bs=1G count=1
	chmod 600 /mnt/home/swapfile
	mkswap /mnt/home/swapfile

	echo /home/swapfile none swap defaults 0 0 >> /mnt/etc/fstab
}

install_packages() {
	arch-chroot /mnt bash -c '
	pacman -S ttf-dejavu wireplumber pipewire-jack phonon-qt5-gstreamer --noconfirm
	pacman -S xorg plasma plasma-wayland-session colord-kde --noconfirm
	pacman -S firefox flatpak gamemode gamescope konsole --noconfirm
	pacman -S git cpupower openvpn partitionmanager pavucontrol powertop xterm xxhash pipewire-pulse --noconfirm

	sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
		
	pacman -Sy steam vulkan-radeon lib32-vulkan-radeon
'
}

create_user() {
	arch-chroot /mnt bash  << EOCHROOT
	useradd -m ${username}
	echo -e "${username}:${password}" | chpasswd
	usermod -aG wheel,audio,video,storage ${username}
	echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
EOCHROOT
}
	
finalize() {
	arch-chroot /mnt bash -c '
	systemctl enable sddm.service
	systemctl enable NetworkManager.service
'
}

create_partitions
format_partitions
prepare_base
create_offload
generate_fstab
create_swap
install_packages
create_user
finalize