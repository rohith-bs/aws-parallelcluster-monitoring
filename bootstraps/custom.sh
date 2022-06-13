yum install -y epel-release \
    singularity \
    git \
    tree \
    glances \
    htop \
    python3-pip \
    python3-devel

# python requirements
pip3 install -U pip numpy pandas tables s3path requests neo4j beautifulsoup4 --use-feature=2020-resolver
pip3 install -U git+https://github.com/Basesolve/toil.git@slurm_partition_5.6.0

# Monitoring requirements
yum -y install docker golang-bin
service docker start
chkconfig docker on
usermod -a -G docker ec2-user

#to be replaced with yum -y install docker-compose as the repository problem is fixed
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /analysis
echo "bind path = /analysis" | tee -a /etc/singularity/singularity.conf
