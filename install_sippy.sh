#!/bin/sh



checkyesno()
{


}

start() {
  echo -n "The script destroys all data on hard disk. Are you sure you want to start? (Yes/No):"
  read yesno
  case $yesno in
    #     "yes", "true", "on", or "1"
    [Yy][Ee][Ss])
      Echo "Start installation"
    ;;

    #     "no", "false", "off", or "0"
    [Nn][Oo])
      echo "Installation abort"
      exit
    ;;
    *)
      return 2
    ;;
  esac
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
  ifaceIp=`ifconfig $iFace| grep inet | grep broad | awk '{print $2}'`
  gwIp=`route -n get default | grep gateway | awk '{print $2}'`
}

setIp() {
  getIp
  getIface
  echo -n "Enter IP address ($ifaceIp, right? Press enter) > "
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

  echo -n "Enter GATEWAY address ($gwIp, right? Press enter) > "
  read gwaddr
  if [ -z $gwaddr ]
  then
    gwaddr=$gwIp
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

  #rc=`gpart add -s 4G -t freebsd-swap -l swap0 /dev/$disk`
  #if [ $? -ne "0" ]
  #then
  #  echo "Error. Something wrong:"
  #fi

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
  `zpool create -R /tmp/zroot -f zroot /dev/gpt/disk0`
  `zfs create -V 4G -o org.freebsd:swap=on -o checksum=off -o compression=off -o dedup=off -o sync=disabled -o primarycache=none zroot/swap`
  `zfs create -o mountpoint=/tmp zroot/tmp`
}

downloadImages() {

  # scp besco@10.101.0.16:./mnt/zfs-images/new/\*.gz /tmp/zroot/tmp
  scp besco@10.101.0.16:./mnt/zfs-images/\*.gz /tmp/zroot/tmp

};

importFs() {
  echo "Restoring /root partition"
  gunzip -c -d /tmp/zroot/tmp/root.gz | zfs receive zroot/root
  rm /tmp/zroot/tmp/root.gz
  echo "Restoring /storage partition"
  gunzip -c -d /tmp/zroot/tmp/storage.gz | zfs receive zroot/storage
  rm /tmp/zroot/tmp/storage.gz
  echo "Restoring /usr partition"
  gunzip -c -d /tmp/zroot/tmp/usr.gz | zfs receive zroot/usr
  rm /tmp/zroot/tmp/usr.gz
  echo "Restoring /usr/home partition"
  gunzip -c -d /tmp/zroot/tmp/usr-home.gz | zfs receive zroot/usr/home
  rm /tmp/zroot/tmp/usr-home.gz

  echo "Restoring /var partition"
  gunzip -c -d /tmp/zroot/tmp/var.gz | zfs receive zroot/var
  rm /tmp/zroot/tmp/var.gz
  echo "Restoring /var/log partition"
  gunzip -c -d /tmp/zroot/tmp/var-log.gz | zfs receive zroot/var/log
  rm /tmp/zroot/tmp/var-log.gz
  echo "Restoring /var/tmp partition"
  gunzip -c -d /tmp/zroot/tmp/var-tmp.gz | zfs receive zroot/var/tmp
  rm /tmp/zroot/tmp/var-tmp.gz

  zpool set bootfs="zroot/root" zroot
  zfs umount -a
  zfs set mountpoint=none zroot
  zfs set mountpoint=/ zroot/root
  zfs set mountpoint=/storage zroot/storage
  zfs set mountpoint=/usr zroot/usr
  zfs set mountpoint=/usr/home zroot/usr/home
  zfs set mountpoint=/var zroot/var
  zfs set mountpoint=/var/log zroot/var/log
  zfs set mountpoint=/var/tmp zroot/var/tmp
  zfs mount -a
  chmod 777 /tmp/zroot/tmp
}

modConfig() {
  cat /tmp/zroot/root/boot/loader.conf | sed 's/rootfs/zroot/g' >/tmp/loader.conf
  cp /tmp/zroot/root/boot/loader.conf /tmp/zroot/root/boot/loader.conf-bk
  cp /tmp/loader.conf /tmp/zroot/root/boot/loader.conf

  cat /tmp/zroot/root/etc/rc.conf | sed 's/^ifconfig/#ifconfig/g' >/tmp/rc.conf
  echo "ifconfig_$iFace=\"inet $ipaddr netmask $netmask\"" >>/tmp/rc.conf
  echo "defaultrouter=\"$gwaddr\"" >>/tmp/rc.conf
  echo "" >>/tmp/rc.conf
  # mv sip-46.166.172.5.sh | sed 's/46.166.172.5/10.99.0.2/g'
  cp /tmp/zroot/root/etc/rc.conf /tmp/zroot/root/etc/rc.conf-bk
  cp /tmp/rc.conf /tmp/zroot/root/etc/rc.conf
  cat /tmp/zroot/usr/local/etc/rc.d/sip-46.166.172.5.sh | sed 's/46.166.172.5/'$ipaddr'/g' >/tmp/zroot/usr/local/etc/rc.d/sip-$ipaddr.sh
  cat /tmp/zroot/root/etc/hosts | sed 's/46.166.172.5/'$ipaddr'/g' >/tmp/zroot/root/etc/hosts.new
  echo "first" >/tmp/zroot/first
  echo "host  all  all  $ipaddr/32  trust" >>/tmp/zroot/var/db/pgsql/data/pg_hba.conf
  echo "first" >/tmp/zroot/first

  echo "#/bin/sh" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "" > /tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "if [ -e /first ];" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "then" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "  psql -U pgsql -d sippy -c \"UPDATE environments SET assigned_ips = '10.99.0.2' WHERE i_environment = 1;\"" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "  rm /first" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  echo "fi" >/tmp/zroot/usr/local/etc/rc.d/change_ip.sh
  chmod +x /tmp/zroot/usr/local/etc/rc.d/change_ip.sh
}

finish() {
  zfs umount -a
}

#start

setIp
getDisk
destroyDisk
createParts
createZFSparts
downloadImages
importFs
modConfig
finish

# UPDATE environments SET assigned_ips = '10.99.0.2' WHERE i_environment = 1;
