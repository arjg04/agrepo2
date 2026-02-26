#!/bin/bash

echo 'Welcome to setup. The setup utility prepares Debian GNU/Linux to run on your computer.'
echo
echo 'To begin setup, press ENTER'
echo 'To exit setup, type Q and press ENTER'
echo 'Hit CTRL+C at any time to quit setup and execute a shell'

read startoption
if [ "$startoption" == 'q' ] ; then 
    echo "Are you sure you want to exit? You will need to rerun setup to finish the installation process. Type yes to quit and press ENTER to continue."
    read startoption2
    if [ $startoption2 == 'yes' ] ; then 
        echo "The system will reboot in 5 seconds."
        sleep 5
        sudo reboot
    fi
fi

if [ "$(cat /sys/firmware/efi/fw_platform_size)" != "64" ] ; then
    echo 'This system has not been boot in 64 bit UEFI mode.'
    echo 'Setup cannot continue. Press ENTER to reboot'
    read quitoption
    sudo reboot
fi

echo 'You need to connect to the internet to download software'
echo 'Enter your WiFi network name (Leave this blank if you are connected by ethernet)'
read wifiname
echo 'Enter your WiFi password (Leave this blank if you are connected by ethernet)'
read wifipassword

wifiinterface=$(ip link | grep -m 1 wl | sed 's/[0-9]: //' | sed 's/:.*//')
echo 'Configuring network interfaces...'
if [ "$wifiname" != '' ] ; then
    sudo bash -c "echo 'auto $wifiinterface' > /etc/network/interfaces ; echo 'iface $wifiinterface inet dhcp' >> /etc/network/interfaces ; echo 'wpa-essid $wifiname' >> /etc/network/interfaces ; echo 'wpa-psk $wifipassword' >> /etc/network/interfaces"
fi
echo 'Restarting network service...'
sudo systemctl restart wpa_supplicant
echo 'Testing connectivity'
ping -c 3 debian.org >> connectivity_replies.txt
if [ $(cat connectivity_replies.txt | wc -l) -eq 0 ] ; then
    echo 'Connection unsuccessful. Setup cannot continue. Press any key to reboot'
    read rebootoption1
    rm -f connectivity_replies.txt
    sudo reboot
fi
rm -f ./connectivity_replies.txt
echo "Connection successful. Press any key to continue"
read continueoption1
sudo apt update
sudo apt install -y debootstrap arch-install-scripts console-data fdisk dosfstools
echo
echo 'Here is a list of all disks, partitions, and block devices on this machine:'
echo 'A partition is a section of a disk that can store data.'
sudo fdisk -l
echo 'Please note that one partition MUST by EFI System!'
echo 'Enter the name of the disk you want to install (e.g. /dev/sda or /dev/nvme0n1)'
echo 'WARNING: if you choose to delete any partitions on the disk, it will erase ALL data on it!'
read disk

sudo cfdisk $disk

for part in $(ls $disk*) ; do
    if [ $part != $disk ] ; then
        echo
        echo "A new partition has been created for $part. Please select an option"
        echo 'a) Format the partition using the EXT4 file system'
        echo 'b) Format the partition using the BTRFS file system'
        echo 'c) Format the partition using the FAT32 file system'
        echo 'd) Set as SWAP device'
        echo 'Please note that the EFI system partition MUST be formatted as FAT32'
        echo 'Please enter an option (a to d), q to quit setup'
        read fsoption
        if [ $fsoption == 'q' ] ; then 
            echo "Are you sure you want to exit? You will need to rerun setup to finish the installation process. Type yes to quit and press ENTER to continue."
            read fsoptionquit
            if [ $fsoptionquit == 'yes' ] ; then 
                echo "The system will reboot in 5 seconds."
                sleep 5
                sudo reboot
            fi
        fi
        echo 'WARNING: ALL DATA on non-removable partition $part WILL BE ERASED! Do you wish to continue (enter yes)'
        read confirmation1
        if [ "$confirmation1" != "yes" ] ; then
            echo 'Setup has not been complete. You will need to rerun setup again to finish the installation process.'
            exit
        fi

        if [ $fsoption == 'a' ] ; then
            sudo mkfs.ext4 $part
        elif [ $fsoption == 'b' ] ; then
            sudo mkfs.btrfs $part
        elif [ $fsoption == 'c' ] ; then
            sudo mkfs.vfat $part
            efidisk=$part
        elif [ $fsoption == 'd' ] ; then
            sudo mkswap $part
            swapdisk=$part
        else 
            echo 'That is not a valid file system. The system will reboot in 5 seconds.'
            sleep 5
            sudo reboot
        fi
    fi
done

for part in $(ls $disk*) ; do
    if [[ $part != $disk && $part != $efidisk && $part != $swapdisk ]] ; then
        echo "Enter the mountpoint for $part"
        read mountpoint
        sudo mount --mkdir $part /mnt$mountpoint
    fi
done

for part in $(ls $disk*) ; do
    if [ $part == $swapdisk ] ; then
        sudo swapon $part
    fi
    if [ $part == $efidisk ] ; then
        sudo mount --mkdir $part /mnt/boot/efi
    fi
done

echo 'Setup is now preparing to install the base system.'
echo 'To begin the installation, press ENTER, or else enter Q to quit setup without installing'
read confirmation2
if [ $confirmation2 == 'q' ] ; then
    echo 'Setup has not finished. You will need to rerun the setup utility to finish the installation process. The system will reboot in 5 seconds.'
    sleep 5
    sudo reboot
fi

sudo debootstrap --arch amd64 stable /mnt http://deb.debian.org/debian
echo
if [ "$wifiname" != '' ] ; then
    sudo bash -c "echo 'auto $wifiinterface' >> /mnt/etc/network/interfaces ; echo 'iface $wifiinterface inet dhcp' >> /mnt/etc/network/interfaces ; echo 'wpa-essid $wifiname' >> /mnt/etc/network/interfaces ; echo 'wpa-psk $wifipassword' >> /mnt/etc/network/interfaces"
fi
sudo bash -c "genfstab -U /mnt > /mnt/etc/fstab"
sudo mount --make-rslave --rbind /proc /mnt/proc
sudo mount --make-rslave --rbind /sys /mnt/sys
sudo mount --make-rslave --rbind /dev /mnt/dev
sudo mount --make-rslave --rbind /run /mnt/run

echo 'Select the type of install you want'
echo 'a) complete'
echo 'b) custom'
read installoption

if [ $installoption == 'a' ] ; then
    echo 'Select the desktop environment you want to install'
    echo 'a) GNOME'
    echo 'b) KDE Plasma'
    read deoption

    if [ $deoption == 'a' ] ; then
        curl https://raw.githubusercontent.com/arjg04/agrepo2/main/sources.list > sources.list
        sudo rm -f /mnt/etc/apt/sources.list
        sudo cp ./sources.list /mnt/etc/apt
        echo 'Enter the name of this computer'
        read computername
        echo 'Enter the new name of the user:'
        read username
        sudo chroot /mnt /bin/bash -c "apt update ; useradd -m -s /bin/bash $username ; echo Enter the password for $username ; passwd $username ; usermod -aG audio,video,sudo $username ; echo $computername > /etc/hostname ; apt install -y linux-image-amd64 firmware-linux efibootmgr os-prober dosfstools mtools vim sudo nano network-manager gnome gnome-system-tools firefox-esr grub-efi-amd64 plymouth-themes wget curl command-not-found net-tools vlc man-db ; echo \"Running command: grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force\" ; grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force ; echo 'GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash vt.global_cursor_default=0\"' > /etc/default/grub ; echo 'GRUB_CMDLINE_LINUX=\"\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT_STYLE=\"hidden\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT=5' >> /etc/default/grub ; echo 'GRUB_BACKGROUND=\\\"\\\"' >> /etc/default/grub ; sed 's/\$(echo \"\$message\" | grub_quote)//g' /etc/grub.d/10_linux > /etc/grub.d/10_linux.bak ; cat /etc/grub.d/10_linux.bak > /etc/grub.d/10_linux ; plymouth-set-default-theme -R bgrt ; update-grub ; systemctl enable NetworkManager ; systemctl enable gdm"
    elif [ $deoption == 'b' ] ; then
        curl https://raw.githubusercontent.com/arjg04/agrepo2/main/sources.list > sources.list
        sudo rm -f /mnt/etc/apt/sources.list
        sudo cp ./sources.list /mnt/etc/apt
        echo 'Enter the name of this computer'
        read hostname
        echo 'Enter the new name of the user:'
        read username
         sudo chroot /mnt /bin/bash -c "apt update ; useradd -m -s /bin/bash $username ; echo Enter the password for $username ; passwd $username ; usermod -aG audio,video,sudo $username ; echo $computername > /etc/hostname ; apt install -y linux-image-amd64 firmware-linux efibootmgr os-prober dosfstools mtools vim sudo nano network-manager kde-standard konsole kate kwrite kio-admin firefox-esr grub-efi-amd64 plymouth-themes wget curl command-not-found net-tools vlc man-db ; echo \"Running command: grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force\" ; grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force ; echo 'GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash vt.global_cursor_default=0\"' > /etc/default/grub ; echo 'GRUB_CMDLINE_LINUX=\"\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT_STYLE=\"hidden\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT=5' >> /etc/default/grub ; echo 'GRUB_BACKGROUND=\"\"' >> /etc/default/grub ; sed 's/\$(echo \"\$message\" | grub_quote)//g' /etc/grub.d/10_linux > /etc/grub.d/10_linux.bak ; cat /etc/grub.d/10_linux.bak > /etc/grub.d/10_linux ; plymouth-set-default-theme -R bgrt ; update-grub ; systemctl enable NetworkManager ; systemctl enable sddm"
    else
        echo 'That is not a valid option. Setup will now exit'
        exit
    fi
elif [ $installoption == 'b' ] ; then
    curl https://raw.githubusercontent.com/arjg04/agrepo2/main/sources.list > sources.list
    sudo rm -f /mnt/etc/apt/sources.list
    sudo cp ./sources.list /mnt/etc/apt
    echo 'Select the desktop environment you want to install'
    echo 'a) GNOME'
    echo 'b) KDE Plasma'
    read deoption
    if [ $deoption == 'a' ] ; then
        echo 'Enter the name of this computer'
        read hostname
        echo 'Enter the new name of the user:'
        read username
        echo 'Install libreoffice suite? (type Y for yes)'
        read yornlibreoffice
        if [ $yornlibreoffice == 'y' ] ; then
            libreoffice='libreoffice'
        else
            libreoffice=''
        fi
        echo 'Install Firefox web browser? (type Y for yes)'
        read yornfirefoxesr
        if [ $yornfirefoxesr == 'y' ] ; then
            firefoxesr='firefox-esr'
        else
            firefoxesr=''
        fi
        echo 'Install gnome-games? (type Y for yes)'
        read yorngnomegames
        if [ $yorngnomegames == 'y' ] ; then
            gnomegames='gnome-games'
        else
            gnomegames=''
        fi
        echo 'Install VLC Media Player? (type Y for yes)'
        read yornvlc
        if [ $yornvlc == 'y' ] ; then
            vlc='vlc'
        else 
            vlc=''
        fi

        echo 'Enable access to additional software (flathub)?'
        read yornflathub
        if [ $yornflathub == 'y' ] ; then
            flathub='flatpak'
            gnomesoftwareflathub='gnome-software-plugin-flatpak'
        else
            flathub=''
            gnomesoftwareflathub=''
        fi
        
        sudo chroot /mnt /bin/bash -c "apt update ; useradd -m -s /bin/bash $username ; echo Enter the password for $username ; passwd $username ; usermod -aG audio,video,sudo $username ; echo $computername > /etc/hostname ; apt install -y linux-image-amd64 firmware-linux efibootmgr os-prober dosfstools mtools vim sudo nano network-manager gnome-shell gdm3 gnome-software $flathub $gnomesoftwareflathub $libreoffice $firefoxesr $gnomegames $vlc nautilus gnome-calculator gnome-system-tools gnome-terminal grub-efi-amd64 plymouth-themes wget curl man-db command-not-found net-tools ; echo \"Running command: grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force\" ; grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force ; echo 'GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash vt.global_cursor_default=0\"' > /etc/default/grub ; echo 'GRUB_CMDLINE_LINUX=\"\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT_STYLE=\"hidden\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT=5' >> /etc/default/grub ; echo 'GRUB_BACKGROUND=\"\"' >> /etc/default/grub ; sed 's/\$(echo \"\$message\" | grub_quote)//g' /etc/grub.d/10_linux > /etc/grub.d/10_linux.bak ; cat /etc/grub.d/10_linux.bak > /etc/grub.d/10_linux ; plymouth-set-default-theme -R bgrt ; flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ; update-grub ; systemctl enable NetworkManager ; systemctl enable gdm"

    elif [ $deoption == 'b' ] ; then
        echo 'Enter the name of this computer'
        read hostname
        echo 'Enter the new name of the user:'
        read username
        echo 'Install libreoffice suite? (type Y for yes)'
        read yornlibreofficekde
        if [ $yornlibreofficekde == 'y' ] ; then
            libreoffice='libreoffice'
        else 
            libreoffice=''
        fi
        echo 'Install Firefox web browser? (type Y for yes)'
        read yornfirefoxesrkde
        if [ $yornforefoxesrkde == 'y' ] ; then
            firefoxesr='firefox-esr'
        else
            firefoxesr=''
        fi
        echo 'Install kde-games? (type Y for yes)'
        read yornkdegames
        if [ $yornkdegames == 'y' ] ; then
            kdegames='kdegames'
        else
            kdegames=''
        fi
        echo 'Install VLC Media Player? (type Y for yes)'
        read yornvlckde
        if [ $yornvlckde == 'y' ] ; then
            vlc='vlc'
        else
            vlc=''
        fi

        echo 'Enable access to additional software (flathub)?'
        read yornflathubkde
        if [ $yornflathubkde == 'y' ] ; then
            flathub='flatpak'
            plasmabackendflathub='plasma-discover-backend-flatpak'
        else
            flathub=''
            plasmabackendflathub=''
        fi
        sudo chroot /mnt /bin/bash -c "apt update ; echo Enter the password for $username ; passwd $username ; usermod -aG audio,video,sudo $username ; echo $computername > /etc/hostname ; apt install -y linux-image-amd64 firmware-linux efibootmgr os-prober dosfstools mtools vim sudo nano network-manager kde-plasma-desktop kcalc konsole kate $libreoffice $firefoxesr $kdegames $vlc $flathub $plasmabackendflathub grub-efi-amd64 plymouth-themes wget curl command-not-found net-tools man-db kio-admin ; echo \"Running command: grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force\" ; grub-install --target=x86_64-efi --bootloader-id=debian --efi-directory=/boot/efi --recheck --force ; echo 'GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash vt.global_cursor_default=0\"' > /etc/default/grub ; echo 'GRUB_CMDLINE_LINUX=\"\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT_STYLE=\"hidden\"' >> /etc/default/grub ; echo 'GRUB_TIMEOUT=5' >> /etc/default/grub ; echo 'GRUB_BACKGROUND=\"\"' >> /etc/default/grub ; sed 's/\$(echo \"\$message\" | grub_quote)//g' /etc/grub.d/10_linux > /etc/grub.d/10_linux.bak ; cat /etc/grub.d/10_linux.bak > /etc/grub.d/10_linux ; flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo plymouth-set-default-theme -R bgrt ; update-grub ; systemctl enable NetworkManager ; systemctl enable gdm"
    else
        echo 'That is not a valid option. Setup will now exit'
        exit
    fi
fi

echo 'Setup has finished configuring your system. You must restart your system for the changes to take effect'
echo 'Press ENTER to reboot'
read rebootoption
sudo reboot
