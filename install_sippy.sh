#!/bin/sh


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
  `zpool set bootfs=zroot zroot`
   
   `zfs create -o mountpoint=/tmp/zroot/tmp zroot/tmp`
}

downloadImages() {

  #`scp besco@10.101.0.16:./mnt/zfs-images/\*.gz /tmp/zroot/tmp`
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/root.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/storage.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/usr-home.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/usr.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/var.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/var-log.gz ./
  scp besco@yabesco.ru:/mnt/ada2/usr/home/besco/111/var-tmp.gz ./

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

setIp
getDisk
#destroyDisk
#createParts
#createZFSparts
#downloadImages
#importFs
#modConfig
#finish
