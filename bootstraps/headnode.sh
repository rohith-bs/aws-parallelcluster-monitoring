echo "bind path = /analysis" | tee -a /etc/singularity/singularity.conf
sed -i 's/16xlarge$/16xlarge RealMemory=124000/' /opt/slurm/etc/pcluster/*_partition.conf
sed -i 's/4xlarge$/4xlarge RealMemory=30000/' /opt/slurm/etc/pcluster/*_partition.conf
sed -i 's/medium$/medium RealMemory=3300/' /opt/slurm/etc/pcluster/*_partition.conf
sed -i 's/alarge$/alarge RealMemory=3300/' /opt/slurm/etc/pcluster/*_partition.conf
yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
yum install -y mysql-community-server mysql-community-client
systemctl enable mysqld
systemctl start mysqld
MYQL_ADMIN_TEMP_PWD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
MYQL_ADMIN_PWD="MyNewStrongP@ssw0d"
mysql -uroot -p${MYQL_ADMIN_TEMP_PWD} --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyNewStrongP@ssw0d';"
mysql -uroot -p${MYQL_ADMIN_PWD} -e "create user 'slurm'@'localhost' identified WITH mysql_native_password by 'Q7F32b0sPGBunBcgT2HW@'; grant all on slurm_acct_db.* TO 'slurm'@'localhost';FLUSH PRIVILEGES;"

echo "Slurm Configuration edits"
sed -i 's/SelectTypeParameters=CR_CPU/SelectTypeParameters=CR_CPU_Memory/' /opt/slurm/etc/slurm.conf
accounting_conf="AccountingStorageType=accounting_storage/slurmdbd\nAccountingStorageHost=$HOSTNAME\nAccountingStorageUser=projectX\nAccountingStoragePort=6819\n# WARNING"
sed -i "s|# WARNING|$accounting_conf|" /opt/slurm/etc/slurm.conf

echo "Slurm DBD setup"
cat << EOF > /opt/slurm/etc/slurmdbd.conf
ArchiveEvents=yes
ArchiveJobs=yes
ArchiveResvs=yes
ArchiveSteps=no
ArchiveSuspend=no
ArchiveTXN=no
ArchiveUsage=no
AuthType=auth/munge
DbdHost=$HOSTNAME
DbdPort=6819
DebugLevel=info
PurgeEventAfter=1month
PurgeJobAfter=12month
PurgeResvAfter=1month
PurgeStepAfter=1month
PurgeSuspendAfter=1month
PurgeTXNAfter=12month
PurgeUsageAfter=24month
SlurmUser=slurm
LogFile=/var/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageUser=slurm
StoragePass=Q7F32b0sPGBunBcgT2HW@
StorageHost=127.0.0.1
StoragePort=3306 
EOF
chmod 600 /opt/slurm/etc/slurmdbd.conf
chown slurm:slurm /opt/slurm/etc/slurmdbd.conf
/opt/slurm/sbin/slurmdbd
systemctl restart slurmctld