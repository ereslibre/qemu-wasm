#!/bin/sh

set -xeu -o pipefail

ip link set dev eth0 up
udhcpc -i eth0

mkdir /mnt/sdb
mount /dev/sdb /mnt/sdb
mkdir /mnt/sdb/boot/
mount /dev/sda /mnt/sdb/boot/

setup-apkrepos -1
BOOTLOADER=none setup-disk -m sys /mnt/sdb/
cp /mnt/sdb/boot/vmlinuz-virt /mnt/sdc1/
KERNEL_VERSION=$(ls /mnt/sdb/lib/modules | head -n 1 | tr -d '\n')

echo 'rc_sys="docker"' >> /mnt/sdb/etc/rc.conf
echo "auto eth0
iface eth0 inet dhcp" > /mnt/sdb/etc/network/interfaces
( chroot /mnt/sdb/ apk add --no-progress --no-cache ca-certificates ) || true
chroot /mnt/sdb/ update-ca-certificates

mkdir -p /mnt/sdb/etc/apk
cat <<'EOF' > /mnt/sdb/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/v3.21/main
http://dl-cdn.alpinelinux.org/alpine/v3.21/community
EOF

chroot /mnt/sdb apk update

PACKAGES=$(cat /mnt/sdc1/packages)
if [ "$PACKAGES" != "" ] ; then
    chroot /mnt/sdb/ apk add --no-progress --no-cache $PACKAGES
fi

SERVICES=$(cat /mnt/sdc1/services)
if [ "$SERVICES" != "" ] ; then
    chroot /mnt/sdb/ apk add --no-progress --no-cache openrc
    for service in $SERVICES; do
        chroot /mnt/sdb/ rc-update add "$service"
    done
fi

mkdir /mnt/sdb/etc/runlevels/additional
cat <<'EOF' >> /mnt/sdb/etc/inittab
# Additional initialization
::once:/sbin/openrc additional &> /dev/null
EOF
chroot /mnt/sdb/ rc-update add qemu-guest-agent boot

cp /mnt/sdc1/root-profile /mnt/sdb/root/.profile
chmod 644 /mnt/sdb/root/.profile

# Original:
# command_args="-m ${GA_METHOD:-virtio-serial} -p ${GA_PATH:-/dev/virtio-ports/org.qemu.guest_agent.0} -l /var/log/qemu-ga.log -d"
cat <<'EOF' > /mnt/sdb/etc/init.d/qemu-guest-agent
#!/sbin/openrc-run

name="QEMU Guest Agent"
pidfile="/run/qemu-ga.pid"
command="/usr/bin/qemu-ga"
command_args="--allow-rpcs='guest-exec,guest-exec-status' -m ${GA_METHOD:-isa-serial} -p /dev/ttyS1 -l /var/log/qemu-ga.log -d"
EOF

apk add --no-progress --no-cache mkinitfs
cp /mnt/sdc1/init.sh /mnt/sdb/sbin/init.sh
chmod 755 /mnt/sdb/sbin/init.sh
mkinitfs -i /mnt/sdb/sbin/init.sh -c /etc/mkinitfs/mkinitfs.conf -b /mnt/sdb/ $KERNEL_VERSION
mv /mnt/sdb/boot/initramfs-virt /mnt/sdc1/

umount /mnt/sdb/boot/
umount /mnt/sdb
