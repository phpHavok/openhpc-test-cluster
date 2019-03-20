#!/bin/bash
# -----------------------------------------------------------------------------------------
#  Example Installation Script Template
#  
#  This convenience script encapsulates command-line instructions highlighted in
#  an OpenHPC Install Guide that can be used as a starting point to perform a local
#  cluster install beginning with bare-metal. Necessary inputs that describe local
#  hardware characteristics, desired network settings, and other customizations
#  are controlled via a companion input file that is used to initialize variables 
#  within this script.
#   
#  Please see the OpenHPC Install Guide(s) for more information regarding the
#  procedure. Note that the section numbering included in this script refers to
#  corresponding sections from the companion install guide.
# -----------------------------------------------------------------------------------------

inputFile=/vagrant/input.local

if [ ! -e ${inputFile} ];then
   echo "Error: Unable to access local input file -> ${inputFile}"
   exit 1
else
   . ${inputFile} || { echo "Error sourcing ${inputFile}"; exit 1; }
fi

# ---------------------------- Begin OpenHPC Recipe ---------------------------------------
# Commands below are extracted from an OpenHPC install guide recipe and are intended for 
# execution on the master SMS host.
# -----------------------------------------------------------------------------------------

# Verify OpenHPC repository has been enabled before proceeding

yum repolist | grep -q OpenHPC
if [ $? -ne 0 ];then
   echo "Error: OpenHPC repository must be enabled locally"
   exit 1
fi

# Disable firewall 
systemctl disable firewalld
systemctl stop firewalld

# ------------------------------------------------------------
# Add baseline OpenHPC and provisioning services (Section 3.3)
# ------------------------------------------------------------
yum -y install ohpc-base
yum -y install ohpc-warewulf
# Enable NTP services on SMS host
systemctl enable ntpd.service
echo "server ${ntp_server}" >> /etc/ntp.conf
systemctl restart ntpd

# -------------------------------------------------------------
# Add resource management services on master node (Section 3.4)
# -------------------------------------------------------------
yum -y install ohpc-slurm-server
perl -pi -e "s/ControlMachine=\S+/ControlMachine=${sms_name}/" /etc/slurm/slurm.conf

# ----------------------------------------
# Update node configuration for slurm.conf
# ----------------------------------------
if [[ ${update_slurm_nodeconfig} -eq 1 ]];then
     perl -pi -e "s/^NodeName=.+$/#/" /etc/slurm/slurm.conf
     perl -pi -e "s/ Nodes=c\S+ / Nodes=c[1-$num_computes] /" /etc/slurm/slurm.conf
     echo -e ${slurm_node_config} >> /etc/slurm/slurm.conf
fi

# -----------------------------------------------------------------------
# Optionally add InfiniBand support services on master node (Section 3.5)
# -----------------------------------------------------------------------
if [[ ${enable_ib} -eq 1 ]];then
     yum -y groupinstall "InfiniBand Support"
     yum -y install infinipath-psm
     systemctl start rdma
fi

# Optionally enable opensm subnet manager
if [[ ${enable_opensm} -eq 1 ]];then
     yum -y install opensm
     systemctl enable opensm
     systemctl start opensm
fi

# Optionally enable IPoIB interface on SMS
if [[ ${enable_ipoib} -eq 1 ]];then
     # Enable ib0
     cp /opt/ohpc/pub/examples/network/centos/ifcfg-ib0 /etc/sysconfig/network-scripts
     perl -pi -e "s/master_ipoib/${sms_ipoib}/" /etc/sysconfig/network-scripts/ifcfg-ib0
     perl -pi -e "s/ipoib_netmask/${ipoib_netmask}/" /etc/sysconfig/network-scripts/ifcfg-ib0
     ifup ib0
fi

# ----------------------------------------------------------------------
# Optionally add Omni-Path support services on master node (Section 3.6)
# ----------------------------------------------------------------------
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install opa-basic-tools
     systemctl start rdma
fi

# Optionally enable OPA fabric manager
if [[ ${enable_opafm} -eq 1 ]];then
     yum -y install opa-fm
     systemctl enable opafm
     systemctl start opafm
fi

# -----------------------------------------------------------
# Complete basic Warewulf setup for master node (Section 3.7)
# -----------------------------------------------------------
perl -pi -e "s/device = eth1/device = ${sms_eth_internal}/" /etc/warewulf/provision.conf
perl -pi -e "s/^\s+disable\s+= yes/ disable = no/" /etc/xinetd.d/tftp
ifconfig ${sms_eth_internal} ${sms_ip} netmask ${internal_netmask} up
systemctl restart xinetd
systemctl enable mariadb.service
systemctl restart mariadb
systemctl enable httpd.service
systemctl restart httpd
systemctl enable dhcpd.service
if [ ! -z ${BOS_MIRROR+x} ]; then
     export YUM_MIRROR=${BOS_MIRROR}
fi

# -------------------------------------------------
# Create compute image for Warewulf (Section 3.8.1)
# -------------------------------------------------
export CHROOT=/opt/ohpc/admin/images/centos7.6
wwmkchroot centos-7 $CHROOT

# ------------------------------------------------------------
# Add OpenHPC base components to compute image (Section 3.8.2)
# ------------------------------------------------------------
yum -y --installroot=$CHROOT install ohpc-base-compute

# -------------------------------------------------------
# Add OpenHPC components to compute image (Section 3.8.2)
# -------------------------------------------------------
cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf
# Add OpenHPC components to compute instance
yum -y --installroot=$CHROOT install ohpc-slurm-client
yum -y --installroot=$CHROOT install ntp
yum -y --installroot=$CHROOT install kernel
yum -y --installroot=$CHROOT install lmod-ohpc

# ----------------------------------------------
# Customize system configuration (Section 3.8.3)
# ----------------------------------------------
wwinit database
wwinit ssh_keys
echo "${sms_ip}:/home /home nfs nfsvers=3,nodev,nosuid 0 0" >> $CHROOT/etc/fstab
echo "${sms_ip}:/opt/ohpc/pub /opt/ohpc/pub nfs nfsvers=3,nodev 0 0" >> $CHROOT/etc/fstab
echo "/home *(rw,no_subtree_check,fsid=10,no_root_squash)" >> /etc/exports
echo "/opt/ohpc/pub *(ro,no_subtree_check,fsid=11)" >> /etc/exports
exportfs -a
systemctl restart nfs-server
systemctl enable nfs-server
chroot $CHROOT systemctl enable ntpd
echo "server ${sms_ip}" >> $CHROOT/etc/ntp.conf

# Update basic slurm configuration if additional computes defined
if [ ${num_computes} -gt 4 ];then
   perl -pi -e "s/^NodeName=(\S+)/NodeName=${compute_prefix}[1-${num_computes}]/" /etc/slurm/slurm.conf
   perl -pi -e "s/^PartitionName=normal Nodes=(\S+)/PartitionName=normal Nodes=${compute_prefix}[1-${num_computes}]/" /etc/slurm/slurm.conf
   perl -pi -e "s/^NodeName=(\S+)/NodeName=${compute_prefix}[1-${num_computes}]/" $CHROOT/etc/slurm/slurm.conf
   perl -pi -e "s/^PartitionName=normal Nodes=(\S+)/PartitionName=normal Nodes=${compute_prefix}[1-${num_computes}]/" $CHROOT/etc/slurm/slurm.conf
fi

# -----------------------------------------
# Additional customizations (Section 3.8.4)
# -----------------------------------------

# Add IB drivers to compute image
if [[ ${enable_ib} -eq 1 ]];then
     yum -y --installroot=$CHROOT groupinstall "InfiniBand Support"
     yum -y --installroot=$CHROOT install infinipath-psm
     chroot $CHROOT systemctl enable rdma
fi
# Add Omni-Path drivers to compute image
if [[ ${enable_opa} -eq 1 ]];then
     yum -y --installroot=$CHROOT install opa-basic-tools
     yum -y --installroot=$CHROOT install libpsm2
     chroot $CHROOT systemctl enable rdma
fi

# Update memlock settings
perl -pi -e 's/# End of file/\* soft memlock unlimited\n$&/s' /etc/security/limits.conf
perl -pi -e 's/# End of file/\* hard memlock unlimited\n$&/s' /etc/security/limits.conf
perl -pi -e 's/# End of file/\* soft memlock unlimited\n$&/s' $CHROOT/etc/security/limits.conf
perl -pi -e 's/# End of file/\* hard memlock unlimited\n$&/s' $CHROOT/etc/security/limits.conf

# Enable slurm pam module
echo "account    required     pam_slurm.so" >> $CHROOT/etc/pam.d/sshd

if [[ ${enable_beegfs_client} -eq 1 ]];then
     wget -P /etc/yum.repos.d https://www.beegfs.io/release/beegfs_6/dists/beegfs-rhel7.repo
     yum -y install kernel-devel gcc
     yum -y install beegfs-client beegfs-helperd beegfs-utils
     perl -pi -e "s/^buildArgs=-j8/buildArgs=-j8 BEEGFS_OPENTK_IBVERBS=1/"  /etc/beegfs/beegfs-client-autobuild.conf
     /opt/beegfs/sbin/beegfs-setup-client -m ${sysmgmtd_host}
     systemctl start beegfs-helperd
     systemctl start beegfs-client
     yum -y install patch
     wget https://www.beegfs.io/release/beegfs_6/0001-client-fix-readdir-in-rhel-7.5.patch  -O /opt/beegfs/src/client/beegfs_client_module_6/0001-client-fix-readdir-in-rhel-7.5.patch
     cd /opt/beegfs/src/client/beegfs_client_module_6
     patch -p2 < 0001-client-fix-readdir-in-rhel-7.5.patch
     /etc/init.d/beegfs-client rebuild
     /etc/init.d/beegfs-client try-restart
     wget -P $CHROOT/etc/yum.repos.d https://www.beegfs.io/release/beegfs_6/dists/beegfs-rhel7.repo
     yum -y --installroot=$CHROOT install beegfs-client beegfs-helperd beegfs-utils
     perl -pi -e "s/^buildEnabled=true/buildEnabled=false/" $CHROOT/etc/beegfs/beegfs-client-autobuild.conf
     rm -f $CHROOT/var/lib/beegfs/client/force-auto-build
     chroot $CHROOT systemctl enable beegfs-helperd beegfs-client
     cp /etc/beegfs/beegfs-client.conf $CHROOT/etc/beegfs/beegfs-client.conf
     echo "drivers += beegfs" >> /etc/warewulf/bootstrap.conf
fi

# Enable Optional packages

if [[ ${enable_lustre_client} -eq 1 ]];then
     # Install Lustre client on master
     yum -y install lustre-client-ohpc
     # Enable lustre in WW compute image
     yum -y --installroot=$CHROOT install lustre-client-ohpc
     mkdir $CHROOT/mnt/lustre
     echo "${mgs_fs_name} /mnt/lustre lustre defaults,localflock,noauto,x-systemd.automount 0 0" >> $CHROOT/etc/fstab
     # Enable o2ib for Lustre
     echo "options lnet networks=o2ib(ib0)" >> /etc/modprobe.d/lustre.conf
     echo "options lnet networks=o2ib(ib0)" >> $CHROOT/etc/modprobe.d/lustre.conf
     # mount Lustre client on master
     mkdir /mnt/lustre
     mount -t lustre -o localflock ${mgs_fs_name} /mnt/lustre
fi


# -------------------------------------------------------
# Configure rsyslog on SMS and computes (Section 3.8.4.7)
# -------------------------------------------------------
perl -pi -e "s/\\#\\\$ModLoad imudp/\\\$ModLoad imudp/" /etc/rsyslog.conf
perl -pi -e "s/\\#\\\$UDPServerRun 514/\\\$UDPServerRun 514/" /etc/rsyslog.conf
systemctl restart rsyslog
echo "*.* @${sms_ip}:514" >> $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^\*\.info/\\#\*\.info/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^authpriv/\\#authpriv/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^mail/\\#mail/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^cron/\\#cron/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^uucp/\\#uucp/" $CHROOT/etc/rsyslog.conf
if [[ ${enable_nagios} -eq 1 ]];then
     # Install Nagios on master and vnfs image
     yum -y install ohpc-nagios
     yum -y --installroot=$CHROOT install nagios-plugins-all-ohpc nrpe-ohpc
     chroot $CHROOT systemctl enable nrpe
     perl -pi -e "s/^allowed_hosts=/# allowed_hosts=/" $CHROOT/etc/nagios/nrpe.cfg
     echo "nrpe 5666/tcp # NRPE"         >> $CHROOT/etc/services
     echo "nrpe : ${sms_ip}  : ALLOW"    >> $CHROOT/etc/hosts.allow
     echo "nrpe : ALL : DENY"            >> $CHROOT/etc/hosts.allow
     chroot $CHROOT /usr/sbin/useradd -c "NRPE user for the NRPE service" -d /var/run/nrpe -r -g nrpe -s /sbin/nologin nrpe
     chroot $CHROOT /usr/sbin/groupadd -r nrpe
     mv /etc/nagios/conf.d/services.cfg.example /etc/nagios/conf.d/services.cfg
     mv /etc/nagios/conf.d/hosts.cfg.example /etc/nagios/conf.d/hosts.cfg
     for ((i=0; i<$num_computes; i++)) ; do
        perl -pi -e "s/HOSTNAME$(($i+1))/${c_name[$i]}/ || s/HOST$(($i+1))_IP/${c_ip[$i]}/" \
        /etc/nagios/conf.d/hosts.cfg
     done
     perl -pi -e "s/ \/bin\/mail/ \/usr\/bin\/mailx/g" /etc/nagios/objects/commands.cfg
     perl -pi -e "s/nagios\@localhost/root\@${sms_name}/" /etc/nagios/objects/contacts.cfg
     echo command[check_ssh]=/usr/lib64/nagios/plugins/check_ssh localhost >> $CHROOT/etc/nagios/nrpe.cfg
     htpasswd -bc /etc/nagios/passwd nagiosadmin ${nagios_web_password}
     chkconfig nagios on
     systemctl start nagios
     chmod u+s `which ping`
fi

if [[ ${enable_ganglia} -eq 1 ]];then
     # Install Ganglia on master
     yum -y install ohpc-ganglia
     yum -y --installroot=$CHROOT install ganglia-gmond-ohpc
     cp /opt/ohpc/pub/examples/ganglia/gmond.conf /etc/ganglia/gmond.conf
     perl -pi -e "s/<sms>/${sms_name}/" /etc/ganglia/gmond.conf
     cp /etc/ganglia/gmond.conf $CHROOT/etc/ganglia/gmond.conf
     echo "gridname MySite" >> /etc/ganglia/gmetad.conf
     systemctl enable gmond
     systemctl enable gmetad
     systemctl start gmond
     systemctl start gmetad
     chroot $CHROOT systemctl enable gmond
     systemctl try-restart httpd
fi

if [[ ${enable_clustershell} -eq 1 ]];then
     # Install clustershell
     yum -y install clustershell-ohpc
     cd /etc/clustershell/groups.d
     mv local.cfg local.cfg.orig
     echo "adm: ${sms_name}" > local.cfg
     echo "compute: ${compute_prefix}[1-${num_computes}]" >> local.cfg
     echo "all: @adm,@compute" >> local.cfg
fi

if [[ ${enable_mrsh} -eq 1 ]];then
     # Install mrsh
     yum -y install mrsh-ohpc mrsh-rsh-compat-ohpc
     yum -y --installroot=$CHROOT install mrsh-ohpc mrsh-rsh-compat-ohpc mrsh-server-ohpc
     echo "mshell          21212/tcp                  # mrshd" >> /etc/services
     echo "mlogin            541/tcp                  # mrlogind" >> /etc/services
     chroot $CHROOT systemctl enable xinetd
fi

if [[ ${enable_genders} -eq 1 ]];then
     # Install genders
     yum -y install genders-ohpc
     echo -e "${sms_name}\tsms" > /etc/genders
     for ((i=0; i<$num_computes; i++)) ; do
        echo -e "${c_name[$i]}\tcompute,bmc=${c_bmc[$i]}"
     done >> /etc/genders
fi

# Optionally, enable conman and configure
if [[ ${enable_ipmisol} -eq 1 ]];then
     yum -y install conman-ohpc
     for ((i=0; i<$num_computes; i++)) ; do
        echo -n 'CONSOLE name="'${c_name[$i]}'" dev="ipmi:'${c_bmc[$i]}'" '
        echo 'ipmiopts="'U:${bmc_username},P:${IPMI_PASSWORD:-undefined},W:solpayloadsize'"'
     done >> /etc/conman.conf
     systemctl enable conman
     systemctl start conman
fi

# Optionally, enable nhc and configure
yum -y install nhc-ohpc
yum -y --installroot=$CHROOT install nhc-ohpc

echo "HealthCheckProgram=/usr/sbin/nhc" >> /etc/slurm/slurm.conf
echo "HealthCheckInterval=300" >> /etc/slurm/slurm.conf  # execute every five minutes

# Optionally, update compute image to support geopm
if [[ ${enable_geopm} -eq 1 ]];then
     export kargs="${kargs} intel_pstate=disable"
fi

if [[ ${enable_geopm} -eq 1 ]];then
     yum -y --installroot=$CHROOT install kmod-msr-safe-ohpc
     yum -y --installroot=$CHROOT install msr-safe-slurm-ohpc
fi

# ----------------------------
# Import files (Section 3.8.5)
# ----------------------------
wwsh file import /etc/passwd
wwsh file import /etc/group
wwsh file import /etc/shadow 
wwsh file import /etc/slurm/slurm.conf
wwsh file import /etc/munge/munge.key

if [[ ${enable_ipoib} -eq 1 ]];then
     wwsh file import /opt/ohpc/pub/examples/network/centos/ifcfg-ib0.ww
     wwsh -y file set ifcfg-ib0.ww --path=/etc/sysconfig/network-scripts/ifcfg-ib0
fi

# --------------------------------------
# Assemble bootstrap image (Section 3.9)
# --------------------------------------
export WW_CONF=/etc/warewulf/bootstrap.conf
echo "drivers += updates/kernel/" >> $WW_CONF
echo "drivers += overlay" >> $WW_CONF
wwbootstrap `uname -r`
# Assemble VNFS
wwvnfs --chroot $CHROOT
# Add hosts to cluster
echo "GATEWAYDEV=${eth_provision}" > /tmp/network.$$
wwsh -y file import /tmp/network.$$ --name network
wwsh -y file set network --path /etc/sysconfig/network --mode=0644 --uid=0
for ((i=0; i<$num_computes; i++)) ; do
   wwsh -y node new ${c_name[i]} --ipaddr=${c_ip[i]} --hwaddr=${c_mac[i]} -D ${eth_provision}
done
# Add hosts to cluster (Cont.)
wwsh -y provision set "${compute_regex}" --vnfs=centos7.6 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,slurm.conf,munge.key,network

# Restart ganglia services to pick up hostfile changes
if [[ ${enable_ganglia} -eq 1 ]];then
  systemctl restart gmond
  systemctl restart gmetad
fi

# Optionally, define IPoIB network settings (required if planning to mount Lustre over IB)
if [[ ${enable_ipoib} -eq 1 ]];then
     for ((i=0; i<$num_computes; i++)) ; do
        wwsh -y node set ${c_name[$i]} -D ib0 --ipaddr=${c_ipoib[$i]} --netmask=${ipoib_netmask}
     done
     wwsh -y provision set "${compute_regex}" --fileadd=ifcfg-ib0.ww
fi

systemctl restart dhcpd
wwsh pxe update

# Optionally, enable user namespaces
export kargs="${kargs} namespace.unpriv_enable=1"
echo "user.max_user_namespaces=15076" >> $CHROOT/etc/sysctl.conf
wwvnfs --chroot $CHROOT

# Optionally, enable console redirection
if [[ ${enable_ipmisol} -eq 1 ]];then
     wwsh -y provision set "${compute_regex}" --console=ttyS1,115200
fi

# Optionally, add arguments to bootstrap kernel
if [[ ${enable_kargs} -eq 1 ]]; then
wwsh -y provision set "${compute_regex}" --kargs="${kargs}"
fi

# ---------------------------------
# Boot compute nodes (Section 3.10)
# ---------------------------------
for ((i=0; i<${num_computes}; i++)) ; do
   ipmitool -E -I lanplus -H ${c_bmc[$i]} -U ${bmc_username} chassis power reset
done

# ---------------------------------------
# Install Development Tools (Section 4.1)
# ---------------------------------------
yum -y install ohpc-autotools
yum -y install EasyBuild-ohpc
yum -y install hwloc-ohpc
yum -y install spack-ohpc
yum -y install valgrind-ohpc

# -------------------------------
# Install Compilers (Section 4.2)
# -------------------------------
yum -y install gnu8-compilers-ohpc

# ----------------------
# Install llvm Compilers
# ----------------------
yum -y install llvm5-compilers-ohpc

# --------------------------------
# Install MPI Stacks (Section 4.3)
# --------------------------------
if [[ ${enable_mpi_defaults} -eq 1 && ${enable_pmix} -eq 0 ]];then
     yum -y install openmpi3-gnu8-ohpc mpich-gnu8-ohpc
elif [[ ${enable_mpi_defaults} -eq 1 && ${enable_pmix} -eq 1 ]];then
     yum -y install openmpi3-pmix-slurm-gnu8-ohpc mpich-gnu8-ohpc
fi

if [[ ${enable_ib} -eq 1 ]];then
     yum -y install mvapich2-gnu8-ohpc
fi
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install mvapich2-psm2-gnu8-ohpc
fi

# ---------------------------------------
# Install Performance Tools (Section 4.4)
# ---------------------------------------
yum -y install ohpc-gnu8-perf-tools

if [[ ${enable_geopm} -eq 1 ]];then
     yum -y install ohpc-gnu8-geopm
fi
yum -y install lmod-defaults-gnu8-openmpi3-ohpc

# ---------------------------------------------------
# Install 3rd Party Libraries and Tools (Section 4.6)
# ---------------------------------------------------
yum -y install ohpc-gnu8-serial-libs
yum -y install ohpc-gnu8-io-libs
yum -y install ohpc-gnu8-python-libs
yum -y install ohpc-gnu8-runtimes
if [[ ${enable_mpi_defaults} -eq 1 ]];then
     yum -y install ohpc-gnu8-mpich-parallel-libs
     yum -y install ohpc-gnu8-openmpi3-parallel-libs
fi
if [[ ${enable_ib} -eq 1 ]];then
     yum -y install ohpc-gnu8-mvapich2-parallel-libs
fi
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install ohpc-gnu8-mvapich2-parallel-libs
fi

# -----------------------------------------------------------------------------------
# Install Optional Development Tools for use with Intel Parallel Studio (Section 4.7)
# -----------------------------------------------------------------------------------
if [[ ${enable_intel_packages} -eq 1 ]];then
     yum -y install intel-compilers-devel-ohpc
     yum -y install intel-mpi-devel-ohpc
     if [[ ${enable_opa} -eq 1 ]];then
          yum -y install mvapich2-psm2-intel-ohpc
     fi
     yum -y install ohpc-intel-serial-libs
     yum -y install ohpc-intel-geopm
     yum -y install ohpc-intel-io-libs
     yum -y install ohpc-intel-perf-tools
     yum -y install ohpc-intel-python-libs
     yum -y install ohpc-intel-runtimes
     yum -y install ohpc-intel-mpich-parallel-libs
     yum -y install ohpc-intel-mvapich2-parallel-libs
     yum -y install ohpc-intel-openmpi3-parallel-libs
     yum -y install ohpc-intel-impi-parallel-libs
fi

# -------------------------------------------------------------
# Allow for optional sleep to wait for provisioning to complete
# -------------------------------------------------------------
sleep ${provision_wait}

# ------------------------------------
# Resource Manager Startup (Section 5)
# ------------------------------------
systemctl enable munge
systemctl enable slurmctld
systemctl start munge
systemctl start slurmctld
pdsh -w $compute_prefix[1-$num_computes] systemctl start slurmd

# Optionally, generate nhc config
pdsh -w c1 "/usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c 
useradd -m test
wwsh file resync passwd shadow group
sleep 2
pdsh -w $compute_prefix[1-$num_computes] /warewulf/bin/wwgetfiles 
