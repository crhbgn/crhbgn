#!/bin/sh

DIALOG=${DIALOG=dialog}
tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$

start() {
  #echo -n "The script destroys all data on hard disk. Are you sure you want to start? (Yes/No):"
  #read yesno
  $DIALOG --clear --defaultno --yesno "The script destroys all data on hard disk. \n\nAre you sure you want to start?" 8 50
  case $? in
    0)
      echo "Start installation"
    ;;

    1)
      echo "Installation abort"
      return 1
    ;;
    255)
      return 2
    ;;
  esac
}

getIface() {
  p=1
  network=""
  trap "rm -f $tempfile" 0 1 2 5 15
  for i in `ifconfig | grep flag | grep -v lo0 | awk '{print \$1}' | sed 's/://g' | xargs`; do
    eval val$p=$i
    network="$network $i <--- off"
    p=`expr $p + 1`
  done
  $DIALOG --no-cancel --title "Network configuration" --clear --radiolist --clear "Select network card" 0 50 10 $network 2>$tempfile
  retval=$?
  choice=`cat $tempfile`
  case $retval in
  0)
    iFace=$choice ;;
  1)
    echo "Abort installation";;
  255)
    echo "Abort installation";;
  esac

  # echo $iFace
}

getIp() {
  ifaceIp=`ifconfig $iFace| grep -m1 inet | grep broad | awk '{print $2}'`
  gwIp=`route -n get default | grep gateway | awk '{print $2}'`
}

setIp() {
  getIface

  getIp
  retval_setIp="-1"
  if [ -z $ipaddr ]
  then
    ipaddr=$ifaceIp
  fi

  if [ -z $netmask ]
  then
    netmask="255.255.255.0"
  fi

  if [ -z $gwaddr ]
  then
    gwaddr=$gwIp
  fi

  exec 3>&1
  VALUES=$(dialog --clear --title "Network configuration" --form "Settings\nCurrent interface: $iFace" 0 0 0 \
    "IP address"    1 0 "$ipaddr"         1 12 30 0 \
    "Netmask   "    2 0 "$netmask"        2 12 30 0 \
    "Gateway   "    3 0 "$gwaddr"         3 12 30 0 \
    2>&1 1>&3)
    retval_set=$?
  case $retval_set in
  0)
    dialog --yesno "Are all the settings correct?\n\nIP addr: $ipaddr\nNetmask: $netmask\nGateway: $gwaddr\n\n" 0 0
    retval_setIp=$?
    case $retval_setIp in
      0)
        return 0
      ;;
      1)
        return 1
      ;;
      255)
        echo ""
        return 2
      ;;
    esac
    ;;
  1)
    echo "Abort installation (cancel)"
    return 1
    ;;
  255)
    echo "Abort installation (esc)"
    return 1
    ;;
  esac
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
  zfs mount -a
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
  # zfs umount -a
  zfs umount zroot/tmp
  zfs destroy zroot/tmp
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
  cat /tmp/zroot/boot/loader.conf | sed 's/rootfs/zroot\/root/g' >/tmp/loader.conf
  cp /tmp/zroot/boot/loader.conf /tmp/zroot/boot/loader.conf-bk
  cp /tmp/loader.conf /tmp/zroot/boot/loader.conf

  cat /tmp/zroot/etc/rc.conf | sed 's/^ifconfig/#ifconfig/g' >/tmp/rc.conf
  echo "ifconfig_$iFace=\"inet $ipaddr netmask $netmask\"" >>/tmp/rc.conf
  echo "defaultrouter=\"$gwaddr\"" >>/tmp/rc.conf
  echo "" >>/tmp/rc.conf
  # mv sip-46.166.172.5.sh | sed 's/46.166.172.5/10.99.0.2/g'
  cp /tmp/zroot/etc/rc.conf /tmp/zroot/etc/rc.conf-bk
  cp /tmp/rc.conf /tmp/zroot/etc/rc.conf
  cat /tmp/zroot/usr/local/etc/rc.d/sip-46.166.172.5.sh | sed 's/46.166.172.5/'$ipaddr'/g' >/tmp/zroot/usr/local/etc/rc.d/sip-$ipaddr.sh
  cat /tmp/zroot/etc/hosts | sed 's/46.166.172.5/'$ipaddr'/g' >/tmp/zroot/etc/hosts.new
  cat /tmp/zroot/usr/local/etc/apache24/httpd-0.conf | sed 's/46.166.172.5/'$ipaddr'/g' >/tmp/zroot/usr/local/etc/apache24/httpd-0.conf-new
  mv /tmp/zroot/usr/local/etc/apache24/httpd-0.conf-new /tmp/zroot/usr/local/etc/apache24/httpd-0.conf
  chmod +x /tmp/zroot/usr/local/etc/rc.d/sip-$ipaddr.sh
  rm /tmp/zroot/usr/local/etc/rc.d/sip-46.166.172.5.sh
  echo "host  all  all  $ipaddr/32  trust" >>/tmp/zroot/var/db/pgsql/data/pg_hba.conf
  echo "first" >/tmp/zroot/first

  echo "#/bin/sh" >/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "" >> /tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "if [ -e /first ];" >>/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "then" >>/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "  /usr/local/bin/psql -U pgsql -d sippy -c \"UPDATE environments SET assigned_ips = '$ipaddr' WHERE i_environment = 1;\"" >>/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "  rm /first" >>/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
  echo "fi" >>/tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh

  chmod +x /tmp/zroot/usr/local/etc/rc.d/sip-0-change_ip.sh
}

finish() {
  #zfs umount -a
}

start
if [ $? -ne 0 ]
  then
    exit $?
  fi

setIp
echo $retval_set

while [ $retval_setIp -ne 0 ]
  do
    if [ $retval_set -eq 1 ]
      then
        exit 1
      fi
    setIp
  done
echo $retval_setIp
#getDisk
#destroyDisk
#createParts
#createZFSparts
#downloadImages
#importFs
#modConfig
#finish

# UPDATE environments SET assigned_ips = '10.99.0.2' WHERE i_environment = 1;
