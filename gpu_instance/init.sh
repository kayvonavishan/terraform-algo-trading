#!/bin/bash

##configure volume
sudo mkdir /data

nvme0n1=`sudo nvme id-ctrl -v /dev/nvme0n1 | grep -Eo vol.*`
nvme1n1=`sudo nvme id-ctrl -v /dev/nvme1n1 | grep -Eo vol.*`
nvme2n1=`sudo nvme id-ctrl -v /dev/nvme2n1 | grep -Eo vol.*`

if [[ "$nvme0n1" == "vol0362d4ea505b3444d" ]]
then
    sudo mkfs -t xfs /dev/nvme0n1
    sudo mount /dev/nvme0n1 /data
elif [[ "$nvme1n1" == "vol0362d4ea505b3444d" ]]
then
    sudo mkfs -t xfs /dev/nvme1n1
    sudo mount /dev/nvme1n1 /data
elif [[ "$nvme2n1" == "vol0362d4ea505b3444d" ]]
then
    sudo mkfs -t xfs /dev/nvme2n1
    sudo mount /dev/nvme2n1 /data
fi

sudo chown -R ubuntu:ubuntu /data
echo "cd /data" > /home/ubuntu/.bash_profile
echo 'eval "$(ssh-agent -s)"' >> /home/ubuntu/.bash_profile
echo "sudo ssh-add -k /data/.ssh/gpu_instance_key_kayvon" >> /home/ubuntu/.bash_profile
echo "sudo ssh-add -k /data/.ssh/gpu_instance_key_dara" >> /home/ubuntu/.bash_profile
sudo chown -R ubuntu:ubuntu /home/ubuntu/.bash_profile

##git config
sudo -i 
echo "Defaults:ubuntu env_keep+=SSH_AUTH_SOCK" >> /etc/sudoers
exit

source activate pytorch
jupyter notebook --generate-config
echo "from notebook.auth import passwd" >> /home/ubuntu/.jupyter/jupyter_notebook_config.py
echo "password = passwd('avishan')" >> /home/ubuntu/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.password = password" >> /home/ubuntu/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.ip = '0.0.0.0'" >> /home/ubuntu/.jupyter/jupyter_notebook_config.py
jupyter notebook &
