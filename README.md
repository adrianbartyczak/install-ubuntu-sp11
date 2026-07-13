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

For this process, you may want to get a fan (large or small) and point it at the back of your Surface Pro, because
during the last step of the Ubuntu installer, your CPU WILL get VERY hot. Additionally, that step sometimes DOESN'T end
for at least 15 minutes because it's building some unnecessary software, so we manually end it after about 5 minutes.

1. Open up the terminal.

2. Edit the following file with vim: > vim /etc/apt/apt.conf.d/20auto-upgrades

3. Change the values of the following variables to "0":
   APT::Periodic::Update-Package-Lists "1";
   APT::Periodic::Unattended-Upgrade "1";

4. In the same terminal, type in (but don't run) the following: > sudo killall -9 ubuntu_bootstrap

5. Keep that command there and minimize the terminal.

6. Start the installer  
   (look at steps 7 - 10 as you go through the installer).

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

1. Clone this repository if you haven't already:
   ```bash
   git clone https://github.com/adrianbartyczak/install-ubuntu-sp11.git
   ```

2. Get into sudo mode by running: > sudo -i

3. Navigate to the scripts directory of this GitHub repository.

4. Run script "fix-wifi-firmware.sh".

5. Run script "fix-bluetooth-firmware.sh".

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
CPU heat a noticeable amount. To install TLP, run the following:
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

From tests, the "powersave" governor significantly reduced CPU heat after about 15 minutes.

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

Windows Hyper-V with Linux still has about twice as better battery life because of the lack of firmware for the
Surface Pro 11 in the Ubuntu Snapdragon concept image (please see my battery test comparisons here):
- <https://github.com/adrianbartyczak/install-ubuntu-sp11/blob/main/other-data/documents/battery-test-comparisons.txt>

Other than that, Wi-Fi, bluetooth, USB and backlight control and working on the Ubuntu Snapdragon concept image. Audio,
touchscreen and screen resolution control (stuck at 2880x1920) are not working.

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

## Linux virtual machine on Windows Hyper-V set up tutorial

Surface Pro 11 purchase note: If you're planning on buying a Surface Pro 11 just to use Windows Hyper-V with Linux, you
                              should 100% get the 32GB version as Windows takes up about 5GB of memory and Hyper-V
                              itself takes up about another 5GB of memory.

### Install Linux (this example uses Debian)

1. Download the net install ISO from Debian's home page  
   (Note: The complete ISO won't work in Windows Hyper-V).

2. Open Windows Hyper-V and click New --> "Virtual Machine...".

3. During the install wizard, select the "Install OS later" option.

4. After finishing setting up the VM, right click on the VM and click on "Settings".

5. Go to "SCSI Controller" and add a "DVD Drive" that points to the Debian net install ISO image.

6. Go to the "Firmware" section and move "DVD Drive" to the top.

7. Start the VM and install Debian.

### Set a custom resolution on the VM

1. Run the following command in PowerShell:
   ```bash
   set-vmvideo -vmname <virtual_machine_name> -horizontalresolution:xxxx -verticalresolution:xxxx -resolutiontype single
   ```

### Enable port-forwarding for VNC in the Debian VM

Notes:
- This requires creating a VMSwitch in PowerShell, which seems to break the internet connection in the VM, and there
  doesn't seem to be a way to fix it. Additionally, doing this kind of breaks the network configuration within your
  Debian VM, preventing your from getting internet ever again, and requiring you to reinstall the VM.
- The best alternative to this is connecting to Windows via VNC and then use your VM from that VNC connection. If VNC
  does not work on your ARM-based PC (as it didn't for me), then you can use Sunshine with Moonlight.

(If anyone knows how to get internet to work inside the VM after doing these steps, please let me know by submitting an
issue.)

1. Open PowerShell and do the following:
   - a. Create a Custom NAT switch:
   ```bash
   New-VMSwitch -SwitchName "MyDebianNatSwitch" -SwitchType Internal
   ```

   - b. Get the new NAT switch's ifIndex and other information:
   ```bash
   Get-NetAdapter -Name "*MyDebianNatSwitch*"
   ```

   - c. Assign a gateway IP to the switch:
   ```bash
   New-NetIPAddress -IPAddress 172.30.50.1 -PrefixLength 24 -InterfaceIndex <ifIndex_from_previous_command>
   ```

   - d. Enable the NAT network routing instance from the VM NAT switch:
   ```bash
   New-NetNat -Name "MyDebianNatSwitch" -InternalIPInterfaceAddressPrefix 172.30.50.0/24
   ```

   - d. Connect the VMSwitch to your VM instance: (optionally, you can select it in your VM's Settings under
   "Network Adapter")
```bash
Connect-VMNetworkAdapter -VMName "<your_vm_name>" -SwitchName "MyDebianNatSwitch"
```

2. (Skip if ran Connect-VMNetworkAdapter) Open up the Settings for the Debian virutal machine.

3. (Skip if ran Connect-VMNetworkAdapter) Select "Network Adapter" from the left and select "MyDebianNatSwitch" and click Ok.

4. Start your Debian VM and create a static IP inside your new network range using the terminal. This is necessary
   because the DHCP server is gone after we changed from the "Default Switch". Open up the terminal and run the
   following:
   ```bash
   sudo ip addr add 172.30.50.120/24 dev eth0
   sudo ip route add default via 172.30.50.1
   ```

   To make it permanent, add the following to /etc/network/interfaces:
auto eth0
iface eth0 inet static
    address 172.30.50.120/24
    gateway 172.30.50.1

5. Finally, return to PowerShell to forward your VNC port on IP address "192.168.100.20":
   ```bash
   Add-NetNatStaticMapping -NatName "MyDebianNatSwitch" -Protocol TCP -ExternalIPAddress "0.0.0.0" -ExternalPort <VNC_port> -InternalIPAddress "192.168.100.20" -InternalPort <VNC_port>
   ```

6. Connect to your VNC server on `<Windows_LAN_IP_address>`:`<VNC_port>`.
   To get your Windows LAN IP address, run "ipconfig" in PowerShell.

### Remove a VM Switch

        To remove a VM Switch, run the following:
```bash
Remove-NetNat -Name "<switch_name>" -Confirm:$false
Remove-VMSwitch -Name "<switch_name>" -Force
```

### Set a max CPU percentage on your Windows machine (to prevent any possibility of overheating; optional)

1. Open Control Panel.

2. Go to System and Security > Power Options.

3. Click Change plan settings next to your active power plan.

4. Click Change advanced power settings.

5. Click the "+" on Processor power management.

6. Click the "+" on Maximum processor state.

7. Set the percentage for both Battery and Plugged in.

### Optimize Windows for better performance (optional)

1. Open the Run application and run "sysdm.cpl".

2. Go to "Advanced" --> "Settings"

3. Click "Optimize Windows for better performance".

## Other Ubuntu ARM images I've tried

linux_ms_dev_kit:
- <https://github.com/jglathe/linux_ms_dev_kit>
- <https://github.com/jglathe/linux_ms_dev_kit/discussions/categories/announcements>

Ubuntu community thread custom images:
- <https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800/1437>
