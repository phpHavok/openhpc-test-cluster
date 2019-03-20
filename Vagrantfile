Vagrant.configure("2") do |config|
    config.vm.box = "centos/7"
    config.vm.box_version = "1902.01"

    config.vm.define "sms", primary: true do |sms|
      sms.vm.provider "virtualbox" do |vboxsms|
        vboxsms.memory = 2048
        vboxsms.cpus = 2
      end
      sms.vm.network "private_network",
                     ip: "192.168.7.2",
                     virtualbox__intnet: "provisioning"
      sms.vm.provision "shell", inline: "echo sms.localdomain > /etc/hostname"
      sms.vm.provision "shell", inline: "yum -y install http://build.openhpc.community/OpenHPC:/1.3/CentOS_7/x86_64/ohpc-release-1.3-1.el7.x86_64.rpm"
      sms.vm.provision "shell", inline: "yum -y install docs-ohpc"
      sms.vm.provision "shell", inline: "sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux"
      sms.vm.provision "shell", inline: "/vagrant/recipe.sh"
    end

    config.vm.define "c1", autostart: false do |c1|
      c1.vm.provider "virtualbox" do |vboxc1|
        vboxc1.memory = 1024
        vboxc1.cpus = 1
        # Enable if you need to debug PXE.
        #vboxc1.gui = 'true'
        vboxc1.customize [
          'modifyvm', :id,
          '--nic1', 'intnet',
          '--intnet1', 'provisioning',
          '--boot1', 'net',
          '--boot2', 'none',
          '--boot3', 'none',
          '--boot4', 'none',
          '--macaddress1', '221a2b111111'
        ]
      end
    end

    config.vm.define "c2", autostart: false do |c2|
      c2.vm.provider "virtualbox" do |vboxc2|
        vboxc2.memory = 1024
        vboxc2.cpus = 1
        # Enable if you need to debug PXE.
        #vboxc2.gui = 'true'
        vboxc2.customize [
          'modifyvm', :id,
          '--nic1', 'intnet',
          '--intnet1', 'provisioning',
          '--boot1', 'net',
          '--boot2', 'none',
          '--boot3', 'none',
          '--boot4', 'none',
          '--macaddress1', '221a2b222222'
        ]
      end
    end
end

# vi: set ft=ruby :
