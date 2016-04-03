#!/bin/sh


start() {
  echo -n "The script destroys all data on hard disk. Are you sure you want to start? (Yes/No):"
  read yesno
  regex = "^([yY][eE][sS]|[yY])$"
  if [ $yesno =~ regex ]
  then
    echo "Installation starting"
  else
    echo "Instalation aborted"
  fi
}

getIface() {
  p=1

  for i in `ifconfig | grep flag | grep -v lo0 | awk '{print \$1}' | sed 's/://g' | xargs`; do
    eval val$p=$i
    echo $p - $val$i
    p=`expr $p + 1`
  done
  echo -n "Select network card (1-`expr $p - 1`)> "
  read numFace
  if [ -z $numFace ]; then
    iFace=$val1
  fi
  p=1
  for i in `ifconfig | grep flag | grep -v lo0 | awk '{print \$1}' | sed 's/://g' | xargs`; do
    if [ $p -eq $numFace ]
    then
      iFace=$i
    fi
    p=`expr $p + 1`
  done
}

getIp() {
  ifaceIp=`ifconfig | grep inet | grep broad | awk '{print $2}'`
  gwIp=`route -n get default | grep gateway | awk '{print $2}'`
}

setIp() {
  getIp
  getIface
  echo -n "Enter IP addres ($ifaceIp, right? Press enter) > "
  read ipaddr
  if [ -z $ipaddr ]
  then
    ipaddr=$ifaceIp
  fi

  echo -n "Enter GATEWAY addres ($gwIp, right? Press enter) > "
  read gwaddr
  if [ -z $gwaddr ]
  then
    gwaddr=$gwIp
  fi

  echo -n "Enter netmask (255.255.255.0, right? Press enter) > "
  read netmask
  if [ -z $netmask ]
  then
    netmask="255.255.255.0"
  fi
  echo ""
  echo "Current settings:"
  echo "IP addr  : $ipaddr"
  echo "Netmask  : $netmask"
  echo "Gateway  : $gwaddr"
  echo "Interface: $iFace"
  echo ""
}


destroyDisk() {
  rc=`gpart destroy -F /dev/$disk`
  if [ $? -ne "0" ]
  then
    #msg=`cat /tmp/inst-rc`
    echo "Destroy failed. Something wrong: $msg"
  fi
}

getDisk() {
  disk=`sysctl kern.disks | awk '{print $2}'`
}

createParts() {
  rc=`gpart create -s gpt /dev/$disk`
  if [ $? -ne "0" ]
  then
    echo "Error. Something wrong:"
  fi

  rc=`gpart add -s 64K -t freebsd-boot /dev/$disk`
  if [ $? -ne "0" ]
  then
    echo "Error. Something wrong:"
  fi

  rc=`gpart add -s 4G -t freebsd-swap -l swap0 /dev/$disk`
  if [ $? -ne "0" ]
  then
    echo "Error. Something wrong:"
  fi

  rc=`gpart add -t freebsd-zfs -l disk0 /dev/$disk`
  if [ $? -ne "0" ]
  then
    echo "Error. Something wrong:"
  fi

  rc=`gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 /dev/$disk`
  if [ $? -ne "0" ]
  then
    echo "Install ZFS bootcode failed. Something wrong: $msg"
  fi

  echo $rc
}


createZFSparts() {
  `zpool create -f zroot /dev/gpt/disk0`
  `zpool set bootfs="zroot/root" zroot`

   `zfs create -o mountpoint=/tmp/zroot/tmp zroot/tmp`
}

downloadImages() {

  #`scp besco@10.101.0.16:./mnt/zfs-images/\*.gz /tmp/zroot/tmp`

};

importFs() {

  gunzip -c -d /tmp/zroot/tmp/root.gz | zfs receive zroot/root
  gunzip -c -d /tmp/zroot/tmp/storage.gz | zfs receive zroot/storage
  gunzip -c -d /tmp/zroot/tmp/usr.gz | zfs receive zroot/usr
  gunzip -c -d /tmp/zroot/tmp/usr-home.gz | zfs receive zroot/usr/home

  gunzip -c -d /tmp/zroot/tmp/var.gz | zfs receive zroot/var
  gunzip -c -d /tmp/zroot/tmp/var-log.gz | zfs receive zroot/var/log
  gunzip -c -d /tmp/zroot/tmp/var-tmp.gz | zfs receive zroot/var/tmp
  zfs set mountpoint=/tmp/zroot zroot
  zfs mount zroot/root
}

modConfig() {
  cat /tmp/zroot/root/boot/loader.conf | sed 's/rootfs/zroot/g' >/tmp/loader.conf
  cp /tmp/zroot/root/boot/loader.conf /tmp/zroot/root/boot/loader.conf-bk
  cp /tmp/loader.conf /tmp/zroot/root/boot/loader.conf

  cat /tmp/zroot/root/etc/rc.conf | sed 's/^ifconfig/#ifconfig/g' >/tmp/rc.conf
  echo "ifconfig_$iFace=\"inet $ipaddr netmask $netmask\"" >>/tmp/rc.conf
  echo "" >>/tmp/rc.conf
  cp /tmp/zroot/root/etc/rc.conf /tmp/zroot/root/etc/rc.conf-bk
  cp /tmp/rc.conf /tmp/zroot/root/etc/rc.conf

}

finish() {
  zfs umount -a
  zfs set mountpoint=/ zroot
  zfs set mountpoint=/ zroot/root
}

start

setIp
getDisk
#destroyDisk
#createParts
#createZFSparts
#downloadImages
#importFs
#modConfig
#finish
