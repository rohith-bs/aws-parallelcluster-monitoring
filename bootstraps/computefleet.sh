echo "bind path = /analysis" | tee -a /etc/singularity/singularity.conf
mkdir -p /work/jobstore/
mkdir -p /job_stores/staged_uploads
ln -s /job_stores/staged_uploads /work/jobstore/
