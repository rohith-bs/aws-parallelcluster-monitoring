echo "bind path = /analysis" | tee -a /etc/singularity/singularity.conf
sudo mkdir -p /work/jobstore/
sudo chown -R 1000:1000 /work/jobstore/
mkdir -p /job_stores/staged_uploads
ln -s /job_stores/staged_uploads /work/jobstore/
