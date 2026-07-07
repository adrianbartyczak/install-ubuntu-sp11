# A complete guide for installing Ubuntu on the Surface Pro 11 X1P/X1E

![ubuntu-sp11](/ubuntu-sp11.jpg)

## 1. Get the ISO

We will be installing the Ubuntu Snapdragon X Elite concept image from here:
- <https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800>  
(Note: It still works on the Snapdragon X1P.)  

This offical page provides the "questing" image file, however, we need the "resolute" image file. When booting the
"questing" image file (on the Surface Pro 11), we get the following error:
"mount: mounting efivarfs on /sys/firmware/efi/efivars failed: Operation not supported".

Please download "resolute-desktop-arm64+x1e.iso" from the following URL:
- <https://people.canonical.com/~platform/images/ubuntu-concept/>

## 2. Create the bootable Ubuntu USB

We need to burn the ISO to the USB drive in a way that allows us to edit the files within the ISO. This is done by
burning the ISO to the USB drive in "ISO" mode rather than in "DD" mode. This will allow us to make the necessary
changes to the files within the ISO.

If you're using Windows, you simply have to use Rufus and edit the files within Windows' File Manager. If you do do
this, skip to step 8.

1. Get the drive letter of the USB drive you're going to be burning the ISO to by running the following:
   ```bash
   ls /dev/sd*
   ```

   This will print something like:
   /dev/sdb  /dev/sdb1

   If you have multiple USB drives connected, you will get something like the following:
   /dev/sdb  /dev/sdb1  /dev/sdc  /dev/sdc1

   In this case, you have to find the drive that you just partitioned. This can be done by running
   "sudo fdisk /dev/sd[DRIVE_LETTER]" and then pressing "p" to verify the partitions. (You can also use
   "df -Pm /dev/[DRIVE_LETTER]1" to check the size of the partition.)

2. Create an EFI System partition using fdisk (NOTE: This WILL erase all data on the USB drive):  

   - a. Run the following: > fdisk /dev/sd[USB_DRIVE_LETTER]
   - b. Create a new GPT partition table by pressing "g"
   - b. Create a partition with at least 15G by pressing "n" and doing the following:  
   Press [Enter] for the default partition; Press [Enter] for the start sector; Type "+15G" for the size; Press [Enter]
   - c. Change the partition type to "EFI System" (1) by pressing "t" and then "1".  
   - d. Write the changes to the disk by pressing "w".

   You can also use GParted instead of fdisk, but I don't have instructions for it.

3. Install "dosfstools" by running the following:
   ```bash
   sudo apt-get install dosfstools
   ```

4. Create a VFAT32 file system for the new USB partition:
   ```bash
   sudo mkfs.vfat -F 32 /dev/sd[USB_DRIVE_LETTER]1
   ```

5. Mount the partition onto a mount directory (like /mnt/usb);
   ```bash
   sudo mkdir -p /mnt/usb; sudo mount /dev/sd[USB_DRIVE_LETTER]1 /mnt/usb
   ```

6. Mount the Ubuntu resolute .iso file onto a mount directory (like /mnt/iso):
   ```bash
   sudo mkdir -p /mnt/iso; sudo mount -o loop <path-to>/resolute-desktop-arm64+x1e.iso /mnt/iso
   ```

7. Copy all the contents and copy all the files that the symbolic links point to.
   We cannot copy the symlinks themselves as they're not allowed on FAT32 file systems. Not copying the symlink source
   files will cause the Ubuntu USB image to boot loop.
   Note: Do not use a dot (".") in place of the asterisk ("*") as this will cause the source files of the symbolic links to
   not get copied.
   ```bash
   sudo cp -rL /mnt/iso/* /mnt/usb/
   ```

8. Remove/delete file "bootaa64.efi" (in EFI/boot) and copy file "grubaa64.efi" as "bootaa64.efi". This fixes Ubuntu
   image from failing to boot:  
   (Credits go to @geocausa [https://github.com/linux-surface/linux-surface/discussions/2128] for this solution.)  
   ```bash
   sudo rm /mnt/usb/EFI/boot/bootaa64.efi; sudo cp /mnt/usb/EFI/boot/grubaa64.efi /mnt/usb/EFI/boot/bootaa64.efi
   ```

9. Unmount the ISO loop deivce and the USB device:
   ```bash
   sudo umount /mnt/iso; sudo umount /mnt/usb
   ```

## 3. Boot into the live USB drive

1. On your Surface Pro 11, press and hold the [Power] and [Volume Up] buttons, releasing the [Power] button once the
   Windows logo appears, and releasing the [Volume Up] button once the UEFI firmware interface appears.

2. In the UEFI firmware interface, go to "Boot Configuration" and move "USB Storage" to the top.

3. Plug in your live USB drive if you haven't already.

4. Exit the UEFI firmware interface and reboot.

## 4. Install Ubuntu

For this process, you want to get a fan (large or small) and point it at the back of your Surface Pro, because during
the last step of the Ubuntu installer, Ubuntu uses the FULL power of your CPU, causing it to get very hot. Additionally,
this step sometimes DOESN'T end on it's own, so we have to manually end it  
(see steps below).

1. Open up the terminal.

2. Edit the following file with vim: > vim /etc/apt/apt.conf.d/20auto-upgrades

3. Change the values of the following variables to "0":
   APT::Periodic::Update-Package-Lists "1";
   APT::Periodic::Unattended-Upgrade "1";

4. In the same terminal, type in (but don't run) the following: > sudo killall -9 ubuntu_bootstrap

5. Keep that command there and minimize the terminal.

6. Start the installer.

7. On the step that asks which internet connection to use, click "Do not connect to internet". This is important so
   it install as few packages as possible during the installation process, which maxes out the CPU and causes it
   to heat up.

8. On the step that asks you to "Install third party software", DO NOT select it. This will cause the installation
   process to more likely fail when we force kill it.

9. At the install step where it asks to install alongside another operating system or remove all operating
   systems, you MUST select "Manual" (so that we can keep Windows):

   When you see the partition table, identify your main drive  
   (should be "/dev/nvme0n1").
   Find where it says "FREE STORAGE" towards the bottom. Click on it, and then on the "+" button at the bottom-left.
   You have to click on it twice setting up the partitions as follows:
   - Boot partition: Size: 440M; File system: ext4; Mountpoint: /boot
   - Root partition: Size: `<size>`G; File system: ext4; Mountpoint: /
   -  
     (Feel free to add any other partition you want.)
   Click Next.

10. For the last step of the installer (clicking Contine on the Review step), you have two options:
   Option 1. Let the installer fully finish (takes about 15 to 30 minutes). Option 2. Run the "sudo killall -9 ubuntu_bootstrap"
   command you typed in the other terminal after about 5 minutes. Option 2. has the risk of the installer not
   getting as far as it needs to, but it does prevent your CPU from being hot for too long. If option 2. causes
   your computer to go to the grub command line after reboot, then you have to run the
   "sudo killall -9 ubuntu_bootstrap" command and the installer about 2 - 3 times before you reboot.

   Now you can point the fan at the back of your Surface Pro if you want.

11. Your CPU may be quite hot after this installation process, so you SHOULD wait at least 2 minutes before rebooting
   your computer.  
   (Keeping the fan on is optional.)

12. After you've waited the 2 minutes, reboot your computer and wait for it to boot into your new Ubuntu install  
   (which should have been placed at the top of the boot order list automatically).  

## 5. Post-Installation steps

These steps are required to make Wi-Fi and Bluetooth work, and to reduce the power draw of Ubuntu on the
Surface Pro 11.

### Fixing Wi-Fi and Bluetooth

1. Clone the "install-ubuntu-sp11" repository if you haven't already:
   ```bash
   git clone https://github.com/adrianbartyczak/install-ubuntu-sp11.git
   ```

2. Get into sudo mode by running: > sudo -i

3. Navigate to the GitHub repository.

4. Run the script "fix-wifi-firmware.sh".

5. Run the script "fix-bluetooth-firmware.sh".

6. Reboot.

7. Check if the Wi-Fi toggle is working. If not, please run "debug-wifi-firmware.sh". It will tell you what
   modules and firmware is missing.

8. Check if Bluetooth is working. If not, run "fix-bluetooth-firmware-method-2.sh", and
   reboot.

   If "fix-bluetooth-firmware-method-1.sh" already fixed bluetooth and you ran "fix-bluetooth-firmware-method-2.sh"
   anyways, then Bluetooth might not work again simply because the service is running. Run the following commands to
   get Bluetooth working again:
   ```bash
   sudo systemctl stop sp11-bt-addr.service
   sudo pkill -9 -f 'btmgmt --index 0'
   sudo systemctl start bluetooth
   ```

Thanks to @kyjus25 for finding the solution to fixing Wi-Fi and Bluetooth on the Surface Pro 11.
You can find his repository here: https://github.com/kyjus25/linux-surface-pro-11-ky

### Lower CPU/GPU heat (and extend battery life)

Ubuntu comes with a package that dynamically adjust system power called "power-profiles-daemon". Installing TLP reduces
CPU and GPU heat a noticeable amount. To install TLP, run the following:
```bash
sudo apt install tlp tlp-rdw
sudo systemctl disable --now power-profiles-daemon
sudo systemctl mask power-profiles-daemon
```

Reboot for changes to take affect.

Get the sp11-get-fw script from Dale's Arch Linux repo and run it. Run the following as root:
```bash
git clone https://github.com/dwhinham/linux-surface-pro-11
cd linux-surface-pro-11
apt-get install -y cabextract curl
./sp11-grab-fw.sh
```

Linux also has things called "power governors". You can list them all by running the following:
```bash
sudo cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
```

You can then set the governor you want to use by running the following:
```bash
sudo apt install linux-tools-common linux-tools-$(uname -r)
sudo cpupower frequency-set -g <governor>
```

From tests, the "powersave" governor significantly reduced CPU heat after about 15 minutes, however, this may have been
caused by something else. It's hard to tell.

Finally, XFCE reduces CPU heat a decent amount in idle mode compared to GNOME from my tests.
If you want to install it, run the following:
```bash
sudo apt install xfce4 xfce4-goodies
```

(During the installation process, select "gdm3" as your display manager [required to enable XFCE later].)  
Then log out or reboot and when you get to the log in screen, click the gear icon at the bottom-right to select your
desktop environment.

### Other steps that may be necessary

- If you run "apt update", you might notice you get an error saying "The repository 'cdrom://...' does not have a
  Release file." To fix this, remove the "cdrom" file in /etc/apt/sources.list.d/.

## Other things

### Windows Hyper-V with Linux vs Ubuntu Snapdragon Concept image

Windows Hyper-V with Linux still has about twice as better battery life because of the lack of firmware in the Ubuntu
Snapdragon concept image for the Surface Pro 11 (please see my battery test comparisons here):
- <https://github.com/adrianbartyczak/install-ubuntu-sp11/blob/main/other-data/documents/battery-test-comparisons.txt>

Other than that, Wi-Fi, bluetooth, USB and backlight control and working on Ubuntu Snapdragon concept image. Audio,
touchscreen and screen resolution control (stuck at 2880x1920) are not working.

### Windows Hyper-V custom resolution

If you're having trouble setting a custom resolution in a Linux virtual machine running in Windows Hyper-V, run the
following command in PowerShell:
```bash
set-vmvideo -vmname <virtual-machine-name> -horizontalresolution:xxxx -verticalresolution:xxxx -resolutiontype single
```

### How to fix UEFI firmware in case it got broken by an image

Sometimes, a rouge image can mess up your UEFI firmware, preventing your computer from booting to a USB drive.
This happened to me, and here are the steps I took to fix it (I'm not sure which part of this process actually fixed it,
but I went through all of these steps):

1. Creating a Surface Pro 11 System Recovery image:
   General steps:
   - a. Open the "Disk Management" section in the "Computer Management" app.
   - b. Add an exFAT partition to the USB drive with at least 20GB.
   - c. Format the partition in File Manager as a FAT partition with a 32MB allocation size.
   - d. Open the "Recovery Image" tool in Windows.
   - e. Create the recovery image on the USB drive partition.  
     (You should be left with directories "EFI" and "sources".)  
   - f. Download the Surface Pro 11 Recovery ZIP file from Microsoft's website.
   - g. Extract the contents of the Surface Pro 11 Recovery ZIP file to the root of the partition  
     (the same location as the "EFI" and "sources" directories).
2. Boot the recovery image USB drive.
3. In the main menu, click the "Restore from drive"(or something similar) option and then select the "Keey my files" or "Erase whole disk" option.
4. The operation will succeed or fail after 99% with a message like "There was a problem recovering the system".
   This will be fixed later on.
5. Go to UEFI settings and toggle Secure Boot  
   (enable or disable, just make it the opposite of what it was).
6. Reboot into Windows  
   (which will fail if the "Restore from drive" setting failed).
7. Repeat steps 5 and 6.
8. Boot into the Surface Pro System Recovery image USB drive again.
9. Go to the Command Prompt.
10. Run the command "bootrec /fixmbr".
11. Reboot back into the Surface Pro System Recovery image USB drive.
12. Like in step 3, click the "Restore from drive" option and restore the drive again.

## Other Ubuntu ARM images I've tried

linux_ms_dev_kit:
- <https://github.com/jglathe/linux_ms_dev_kit>
- <https://github.com/jglathe/linux_ms_dev_kit/discussions/categories/announcements>

Ubuntu community thread custom images:
- <https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800/1437>
