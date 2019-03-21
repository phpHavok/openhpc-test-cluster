#!/bin/bash

NCOMPUTES="$1"
if [ -z "$NCOMPUTES" ] || [ "$NCOMPUTES" -lt 1 ] || [ "$NCOMPUTES" -gt 10 ]; then
    echo "You must request between 1 and 10 compute nodes ($NCOMPUTES requested)."
    exit 1
fi

COMPUTE_DEFS=""
VAGRANT_DEFS=""
for ((i=1;i<=NCOMPUTES;i++)); do
    COMPUTE_DEFS+=`cat <<EOF
c_name[$((i-1))]=c$i
c_ip[$((i-1))]=192.168.7.$((i+2))
c_mac[$((i-1))]=22:1a:2b:00:00:$((i-1))$((i-1))
EOF`
    COMPUTE_DEFS+=$'\n'
    VAGRANT_DEFS+=`cat <<EOF
    config.vm.define "c$i", autostart: false do |c$i|
      c$i.vm.provider "virtualbox" do |vboxc$i|
        vboxc$i.memory = 2048
        vboxc$i.cpus = 1
        # Enable if you need to debug PXE.
        #vboxc$i.gui = 'true'
        vboxc$i.customize [
          'modifyvm', :id,
          '--nic1', 'intnet',
          '--intnet1', 'provisioning',
          '--boot1', 'net',
          '--boot2', 'none',
          '--boot3', 'none',
          '--boot4', 'none',
          '--macaddress1', '221a2b0000$((i-1))$((i-1))'
        ]
      end
      c$i.vm.boot_timeout = 10
    end
EOF`
    VAGRANT_DEFS+=$'\n'
done

cp recipe.sh.tmpl cluster/recipe.sh
sed "s/<NCOMPUTES>/$NCOMPUTES/g;" input.local.tmpl > cluster/input.local
echo "$COMPUTE_DEFS" >> cluster/input.local
cp Vagrantfile.header.tmpl cluster/Vagrantfile
echo "$VAGRANT_DEFS" >> cluster/Vagrantfile
cat Vagrantfile.footer.tmpl >> cluster/Vagrantfile
