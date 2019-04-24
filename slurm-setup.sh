#1/bin/bash
systemctl start slurmdbd
sleep 5
sacctmgr -i add cluster linux
sacctmgr -i add account projects
sacctmgr -i add account proj1 parent=projects
sacctmgr -i add account proj2 parent=projects
sacctmgr -i add user test1 account=proj1
sacctmgr -i add user test2 account=proj2
sacctmgr -i add user test3 account=proj2
systemctl start slurmctld
