#!/bin/bash -i
#
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
#

#source the AWS ParallelCluster profile
. /etc/parallelcluster/cfnconfig

if [ ! -x "$(command -v docker)" ]; then
	echo "Setting Up docker in rootless mode"
	curl -fsSL https://get.docker.com | sh 
	apt install -y uidmap 
	dockerd-rootless-setuptool.sh install
	echo "systemctl --user start docker" | sudo -u ${cfn_cluster_user}
	echo "systemctl --user enable docker" | sudo -u ${cfn_cluster_user}
	loginctl enable-linger ${cfn_cluster_user}
	echo "export PATH=/usr/bin:\$PATH" >> /home/${cfn_cluster_user}/.bashrc
	echo "export DOCKER_HOST=unix:///run/user/1000/docker.sock" >> /home/${cfn_cluster_user}/.bashrc
else
	echo "Docker is already installed [skipping]."
fi

apt install -y docker-compose

monitoring_dir_name=$(echo ${cfn_postinstall_args}| cut -d ',' -f 2 )
monitoring_home="/home/${cfn_cluster_user}/${monitoring_dir_name}"

case "${cfn_node_type}" in
	MasterServer)

		#cfn_efs=$(cat /etc/chef/dna.json | grep \"cfn_efs\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		#cfn_cluster_cw_logging_enabled=$(cat /etc/chef/dna.json | grep \"cfn_cluster_cw_logging_enabled\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cfn_fsx_fs_id=$(cat /etc/chef/dna.json | grep \"cfn_fsx_fs_id\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		master_instance_id=$(ec2-metadata -i | awk '{print $2}')
		cfn_max_queue_size=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "MaxSize"))[0].ParameterValue')
		s3_bucket=$(echo $cfn_postinstall | sed "s/s3:\/\///g;s/\/.*//")
		cluster_s3_bucket=$(cat /etc/chef/dna.json | grep \"cluster_s3_bucket\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_s3_key=$(cat /etc/chef/dna.json | grep \"cluster_config_s3_key\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_version=$(cat /etc/chef/dna.json | grep \"cluster_config_version\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		log_group_names="\/aws\/parallelcluster\/$(echo ${stack_name} | cut -d "-" -f2-)"

		aws s3api get-object --bucket $cluster_s3_bucket --key $cluster_config_s3_key --region $cfn_region --version-id $cluster_config_version ${monitoring_home}/parallelcluster-setup/cluster-config.json

		if [ ! -x "$(command -v go)" ]; then
			export GVERSION=1.14.12 OS=linux ARCH=amd64
			echo "Setting up GO"
			wget -c https://dl.google.com/go/go$GVERSION.$OS-$ARCH.tar.gz 
			tar -xzf go$GVERSION.$OS-$ARCH.tar.gz -C /usr/local/ && rm go$GVERSION.$OS-$ARCH.tar.gz
			ln -s /usr/local/go/bin/go /usr/bin/go
			echo "Go Set-up Complete: $(go version)"
		else
			echo "Go installation exists. [skipping]"
		fi

		chown $cfn_cluster_user:$cfn_cluster_user -R /home/$cfn_cluster_user
		chmod +x ${monitoring_home}/custom-metrics/* 

		cp -rp ${monitoring_home}/custom-metrics/* /usr/local/bin/
		mv ${monitoring_home}/prometheus-slurm-exporter/slurm_exporter.service /etc/systemd/system/

	 	(crontab -l -u $cfn_cluster_user; echo "*/1 * * * * /usr/local/bin/1m-cost-metrics.sh") | crontab -u $cfn_cluster_user -
		(crontab -l -u $cfn_cluster_user; echo "*/60 * * * * /usr/local/bin/1h-cost-metrics.sh") | crontab -u $cfn_cluster_user - 


		# replace tokens 
		sed -i "s/_S3_BUCKET_/${s3_bucket}/g"               	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/ParallelCluster.json 
		sed -i "s/__FSX_ID__/${cfn_fsx_fs_id}/g"            	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/ParallelCluster.json 

		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/logs.json
		sed -i "s/__LOG_GROUP__NAMES__/${log_group_names}/g"    ${monitoring_home}/grafana/dashboards/logs.json

		sed -i "s/__Application__/${stack_name}/g"          	${monitoring_home}/prometheus/prometheus.yml 

		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/master-node-details.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-list.json 
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-details.json 

		sed -i "s/__MONITORING_DIR__/${monitoring_dir_name}/g"  ${monitoring_home}/docker-compose/docker-compose.master.yml

		#Generate selfsigned certificate for Nginx over ssl
		nginx_dir="${monitoring_home}/nginx"
		nginx_ssl_dir="${nginx_dir}/ssl"
		mkdir -p ${nginx_ssl_dir}
		echo -e "\nDNS.1=$(ec2-metadata -p | awk '{print $2}')" >> "${nginx_dir}/openssl.cnf"
		openssl req -new -x509 -nodes -newkey rsa:4096 -days 3650 -keyout "${nginx_ssl_dir}/nginx.key" -out "${nginx_ssl_dir}/nginx.crt" -config "${nginx_dir}/openssl.cnf"

		#give $cfn_cluster_user ownership 
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.key"
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.crt"

		/usr/local/bin/docker-compose --env-file /etc/parallelcluster/cfnconfig -f ${monitoring_home}/docker-compose/docker-compose.master.yml -p monitoring-master up -d

		# Download and build prometheus-slurm-exporter 
		##### Plese note this software package is under GPLv3 License #####
		# More info here: https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE
		cd ${monitoring_home}
		git clone https://github.com/rohith-bs/prometheus-slurm-exporter.git
		cd prometheus-slurm-exporter
		GOPATH=/root/go-modules-cache HOME=/root go mod download
		GOPATH=/root/go-modules-cache HOME=/root go build
		mv ${monitoring_home}/prometheus-slurm-exporter/prometheus-slurm-exporter /usr/bin/prometheus-slurm-exporter

		systemctl daemon-reload
		systemctl enable slurm_exporter
		systemctl start slurm_exporter
	;;

	ComputeFleet)
		compute_instance_type=$(ec2-metadata -t | awk '{print $2}')
		gpu_instances="[pg][2-9].*\.[0-9]*[x]*large"
		if [[ $compute_instance_type =~ $gpu_instances ]]; then
			distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
			curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
			curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list

			apt-get update && sudo apt-get install -y nvidia-container-toolkit
			systemctl restart docker
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.gpu.yml -p monitoring-compute up -d
        	else
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.yml -p monitoring-compute up -d
        	fi
	;;
	*)
	;;
esac
