#!/bin/bash

DRIVE="/dev/nvme0n1"
BOOT_PARTITION="${DRIVE}p1"
SWAP_PARTITION="${DRIVE}p2"
HOME_PARTITION="${DRIVE}p3"
HOSTNAME="archlinux"
ROOT_PASSWORD="root"
USERNAME="nolanwesl3y"
USER_PASSWORD="user"
TIMEZONE="Asia/Bangkok"
MIRROR_REGION="Thailand"
KEYMAP="us"
VIDEO_DRIVER="i915"
PACKAGES="grub efibootmgr networkmanager network-manager-applet dialog mtools dosfstools wpa_supplicant git reflector bash-completion base-devel linux-headers bluez bluez-utils cups xdg-utils xdg-user-dirs rsync inetutils dnsutils nfs-utils gvfs gvfs-smb openssh xf86-video-intel"

setup() {
    # Check network connection
    echo "Checking internet connection..."
    ping -c 3 google.com > /dev/null 2>&1

    # Check the exit status of the ping command
    if [[ $? -eq 0 ]]; then
        echo "Internet connection is available."
    else
        echo "No internet connection. Exiting..."
        exit 1
    fi

    echo "Fetching fastest mirror for $MIRROR_REGION..."
    reflector -c $MIRROR_REGION -a 6 --sort rate --save /etc/pacman.d/mirrorlist
    
    echo "Creating partitions on $DRIVE..."
    parted --script "$DRIVE" \
    mklabel gpt \
    mkpart primary fat32 1MiB 512MiB \
    set 1 boot on \
    mkpart primary linux-swap 512MiB 8GiB \
    mkpart primary ext4 8GiB 100%
    
    echo 'Formating partitions...'
    mkfs.fat -F 32 "$BOOT_PARTITION"
    mkswap "${SWAP_PARTITION}"
    mkfs.ext4 "${HOME_PARTITION}"
    
    echo 'Mounting filesystems...'
    mount "${HOME_PARTITION}" /mnt
    mount --mkdir "$BOOT_PARTITION" /mnt/boot/efi
    swapon "${SWAP_PARTITION}"
    
    echo 'Installing base...'
    pacstrap /mnt base linux linux-firmware vim intel-ucode sof-firmware
    
    echo 'Generating fstab...'
    genfstab -U /mnt >> /mnt/etc/fstab
    
    echo 'Chrooting into installed system to continue setup...'
    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot
    
    if [ -f /mnt/setup.sh ]
    then
        echo 'ERROR: Something failed inside the chroot, not unmounting filesystems so you can investigate.'
        echo 'Make sure you unmount everything before you try to run this script again.'
    else
        exit
        unmount -a
        echo "Arch Linux installation complete. Press enter to reboot."
        read
        reboot
    fi
}

configure() {
    echo "Initalizing timezone..."
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    hwclock --systohc
    
    echo 'Setting locale...'
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" >> /etc/locale.conf
    
    echo 'Setting console keymap...'
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    
    echo 'Setting hostname...'
    echo "$HOSTNAME" >> /etc/hostname
    
    
    echo 'Setting hosts file...'
    cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF
    
    echo 'Setting root password...'
    echo -en "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd
    
    echo 'Installing packages...'
    pacman -Sy --noconfirm $PACKAGES
    
    echo 'Configuring initial ramdisk...'
    cat > /etc/mkinitcpio.conf <<EOF
# vim:set ft=sh
# MODULES
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES=(usbhid xhci_hcd)
MODULES=($VIDEO_DRIVER)

# BINARIES
# This setting includes any additional binaries a given user may
# wish into the CPIO image.  This is run last, so it may be used to
# override the actual binaries included by a given hook
# BINARIES are dependency parsed, so you may safely ignore libraries
BINARIES=()

# FILES
# This setting is similar to BINARIES above, however, files are added
# as-is and are not parsed in any way.  This is useful for config files.
FILES=()

# HOOKS
# This is the most important setting in this file.  The HOOKS control the
# modules and scripts added to the image, and what happens at boot time.
# Order is important, and it is recommended that you do not change the
# order in which HOOKS are added.  Run 'mkinitcpio -H <hook name>' for
# help on a given hook.
# 'base' is _required_ unless you know precisely what you are doing.
# 'udev' is _required_ in order to automatically load modules
# 'filesystems' is _required_ unless you specify your fs modules in MODULES
# Examples:
##   This setup specifies all modules in the MODULES setting above.
##   No RAID, lvm2, or encrypted root is needed.
#    HOOKS=(base)
#
##   This setup will autodetect all modules for your system and should
##   work as a sane default
#    HOOKS=(base udev autodetect modconf block filesystems fsck)
#
##   This setup will generate a 'full' image which supports most systems.
##   No autodetection is done.
#    HOOKS=(base udev modconf block filesystems fsck)
#
##   This setup assembles a mdadm array with an encrypted root file system.
##   Note: See 'mkinitcpio -H mdadm_udev' for more information on RAID devices.
#    HOOKS=(base udev modconf keyboard keymap consolefont block mdadm_udev encrypt filesystems fsck)
#
##   This setup loads an lvm2 volume group.
#    HOOKS=(base udev modconf block lvm2 filesystems fsck)
#
##   NOTE: If you have /usr on a separate partition, you MUST include the
#    usr and fsck hooks.
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)

# COMPRESSION
# Use this to compress the initramfs image. By default, zstd compression
# is used. Use 'cat' to create an uncompressed image.
#COMPRESSION="zstd"
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"
#COMPRESSION="lz4"

# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=()

# MODULES_DECOMPRESS
# Decompress kernel modules during initramfs creation.
# Enable to speedup boot process, disable to save RAM
# during early userspace. Switch (yes/no).
#MODULES_DECOMPRESS="yes"
EOF
    
    mkinitcpio -p linux
    
    echo 'Setting GRUB...'
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    
    echo 'Setting initial daemons...'
    systemctl enable NetworkManager bluetooth cups sshd reflector.timer fstrim.timer
    
    echo 'Setting user...'
    useradd -mG wheel $USERNAME
    echo -en "$USER_PASSWORD\n$USER_PASSWORD" | passwd "$USERNAME"
    
    echo 'Configuring sudoers...'
    cat > /etc/sudoers <<EOF
## sudoers file.
##
## This file MUST be edited with the 'visudo' command as root.
## Failure to use 'visudo' may result in syntax or file permission errors
## that prevent sudo from running.
##
## See the sudoers man page for the details on how to write a sudoers file.
##

##
## Host alias specification
##
## Groups of machines. These may include host names (optionally with wildcards),
## IP addresses, network numbers or netgroups.
# Host_Alias    WEBSERVERS = www1, www2, www3

##
## User alias specification
##
## Groups of users.  These may consist of user names, uids, Unix groups,
## or netgroups.
# User_Alias    ADMINS = millert, dowdy, mikef

##
## Cmnd alias specification
##
## Groups of commands.  Often used to group related commands together.
# Cmnd_Alias    PROCESSES = /usr/bin/nice, /bin/kill, /usr/bin/renice, \
#                           /usr/bin/pkill, /usr/bin/top
# Cmnd_Alias    REBOOT = /sbin/halt, /sbin/reboot, /sbin/poweroff

##
## Defaults specification
##
## You may wish to keep some of the following environment variables
## when running commands via sudo.
##
## Locale settings
# Defaults env_keep += "LANG LANGUAGE LINGUAS LC_* _XKB_CHARSET"
##
## Run X applications through sudo; HOME is used to find the
## .Xauthority file.  Note that other programs use HOME to find
## configuration files and this may lead to privilege escalation!
# Defaults env_keep += "HOME"
##
## X11 resource path settings
# Defaults env_keep += "XAPPLRESDIR XFILESEARCHPATH XUSERFILESEARCHPATH"
##
## Desktop path settings
# Defaults env_keep += "QTDIR KDEDIR"
##
## Allow sudo-run commands to inherit the callers' ConsoleKit session
# Defaults env_keep += "XDG_SESSION_COOKIE"
##
## Uncomment to enable special input methods.  Care should be taken as
## this may allow users to subvert the command being run via sudo.
# Defaults env_keep += "XMODIFIERS GTK_IM_MODULE QT_IM_MODULE QT_IM_SWITCHER"
##
## Uncomment to use a hard-coded PATH instead of the user's to find commands
# Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
##
## Uncomment to send mail if the user does not enter the correct password.
# Defaults mail_badpass
##
## Uncomment to enable logging of a command's output, except for
## sudoreplay and reboot.  Use sudoreplay to play back logged sessions.
## Sudo will create up to 2,176,782,336 I/O logs before recycling them.
## Set maxseq to a smaller number if you don't have unlimited disk space.
# Defaults log_output
# Defaults!/usr/bin/sudoreplay !log_output
# Defaults!/usr/local/bin/sudoreplay !log_output
# Defaults!REBOOT !log_output
# Defaults maxseq = 1000

##
## Runas alias specification
##

##
## User privilege specification
##
root ALL=(ALL:ALL) ALL

## Uncomment to allow members of group wheel to execute any command
%wheel ALL=(ALL:ALL) ALL

## Same thing without a password
# %wheel ALL=(ALL:ALL) NOPASSWD: ALL

## Uncomment to allow members of group sudo to execute any command
# %sudo ALL=(ALL:ALL) ALL

## Uncomment to allow any user to run sudo if they know the password
## of the user they are running the command as (root by default).
# Defaults targetpw  # Ask for the password of the target user
# ALL ALL=(ALL:ALL) ALL  # WARNING: only use this together with 'Defaults targetpw'

## Read drop-in files from /etc/sudoers.d
@includedir /etc/sudoers.d
EOF
    
    chmod 440 /etc/sudoers

    rm /setup.sh
}

set -ex

if [ "$1" == "chroot" ]
then
    configure
else
    setup
fi