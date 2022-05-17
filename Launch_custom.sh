#/bin/sh

# Add extra kexts to EFI/OC/kexts

# Rebuild Opencore.qcow2 after making changes to config.plist and etc..
echo 'Building new Opencore.qcow2..'
pushd OpenCore-Catalina/
sudo mkdir -p EFI/OC/Resources
rm -f OpenCore.qcow2
sudo ./opencore-image-ng.sh \
  --cfg config.plist \
  --img OpenCore.qcow2
sudo chown ubuntu:ubuntu OpenCore.qcow2
popd

if ! [ -d "/system_image/installers" ]; then
  sudo mkdir -p /system_image/installers
fi

if ! [ -d "/system_image/osx-builder" ]; then
  sudo mkdir -p "/system_image/osx-builder"
fi

# Download and build installer image if no system drive found..
if ! [ -f "/system_image/installers/BaseSystem10.15.7.img" ]; then
  echo "Downloading 10.15.7 base image.."
  python fetch-macOS.py --version 10.15.7
  echo 'Converting downloaded BaseSystem.dmg into BaseSystem10.15.7.img and saving in '
  qemu-img convert BaseSystem.dmg -O qcow2 -p -c /system_image/installers/BaseSystem.img
  rm -f BaseSystem.dmg
else
  echo 'Base Image downloaded and converted into img already..'
fi

if ! [ -f "/system_image/osx-builder/mac_hdd_ng.img" ]; then
  echo "Creating a 250G /system_image/osx-builder/mac_hdd_ng.img for system partition.."
  qemu-img create -f qcow2 /system_image/osx-builder/mac_hdd_ng.img "250G"
  echo 'Finished creating system partition!'
else
  echo 'Image already created. Skipping creation..'
fi

# # Fix permissions on usb devices..
#

# Start VNC..
echo 'geometry=1920x1080
localhost
alwaysshared' > ~/.vnc/config

sudo rm -f /tmp/.X99-lock
export DISPLAY=:99
vncpasswd -f < vncpasswd_file > ${HOME}/.vnc/passwd
/usr/bin/Xvnc -geometry 1920x1080 -rfbauth "${HOME}/.vnc/passwd" :99 &\
sudo chmod 600 ~/.vnc/passwd

sudo chown ubuntu:ubuntu /dev/kvm

# Start QEMU..
echo 'Starting QEMU..'
set -eu
sudo chown    $(id -u):$(id -g) /dev/kvm 2>/dev/null || true
sudo chown -R $(id -u):$(id -g) /dev/snd 2>/dev/null || true
exec qemu-system-x86_64 -m 8000M \
  -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+pcid,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+xsave,+xsaveopt,check \
  -machine q35,accel=kvm:tcg \-vga vmware \
  -smp 4,cores=4 \
    -usb -device usb-kbd -device usb-tablet \
  -device isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal\(c\)AppleComputerInc \
  -drive if=pflash,format=raw,readonly,file=/home/ubuntu/OSX-KVM/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/home/ubuntu/OSX-KVM/OVMF_VARS-1024x768.fd \
  -smbios type=2 \
  -device ich9-ahci,id=sata \
  -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=/home/ubuntu/OSX-KVM/OpenCore-Catalina/OpenCore.qcow2 \
  -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
  -drive id=MacHDD,if=none,file=/system_image/osx-builder/mac_hdd_ng.img,format=qcow2 \
  -device ide-hd,bus=sata.4,drive=MacHDD \
  -netdev user,id=net0,hostfwd=tcp::${INTERNAL_SSH_PORT:-10022}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT:-5900}-:5900,hostfwd=tcp::5901-:5900 \
  -device e1000-82545em,netdev=net0,id=net0,mac=52:54:00:09:49:17 \
  ${EXTRA:-}
