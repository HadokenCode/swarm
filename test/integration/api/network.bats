#!/usr/bin/env bats

load ../helpers

function teardown() {
	swarm_manage_cleanup
	stop_docker
}

@test "docker network ls" {
	start_docker 2
	swarm_manage

	run docker_swarm network ls
	[ "${#lines[@]}" -eq 7 ]
}

@test "docker network ls --filter type" {
	start_docker 2
	swarm_manage

	run docker_swarm network ls --filter type=builtin
	[ "${#lines[@]}" -eq 7 ]

	run docker_swarm network ls --filter type=custom
	[ "${#lines[@]}" -eq 1 ]

	run docker_swarm network ls --filter type=foo
	[ "$status" -ne 0 ]

	docker_swarm network create -d bridge test
	run docker_swarm network ls
	[ "${#lines[@]}" -eq 8 ]

	run docker_swarm network ls --filter type=custom
	[ "${#lines[@]}" -eq 2 ]
}

# docker network ls --filter node returns networks that are present on a specific node
@test "docker network ls --filter node" {
	start_docker 2
	swarm_manage

	run docker_swarm network ls --filter node=node-0
	[ "${#lines[@]}" -eq 4 ]

	run docker_swarm network ls --filter node=node-1
	[ "${#lines[@]}" -eq 4 ]
}

# docker network ls --filter name returns networks that match with a provided name
@test "docker network ls --filter name" {
	# don't bother running this for older versions
	run docker --version
	if [[ "${output}" == "Docker version 1.12"* || "${output}" == "Docker version 1.13"* ]]; then
			skip
	fi

	start_docker 2
	swarm_manage

	run docker_swarm network create networknameone
	run docker_swarm network create networknametwo

	run docker_swarm network ls
	echo $output

	run docker_swarm network ls --filter name=networkname
	echo $output
	[ "${#lines[@]}" -eq 3 ]
}

@test "docker network inspect" {
	# Docker 1.12 client shows "Attachable" and "Created" fields while docker daemon 1.12
	# doesn't return them. Network inspect from Swarm is different from daemon.
	run docker --version
	if [[ "${output}" == "Docker version 1.12"* ]]; then
		skip
	fi

	# Docker 1.13, 17.03 client shows "Ingress" and "ConfigFrom" fields while docker daemon 1.13
	# doesn't return them. Network inspect from Swarm is different from daemon.
	run docker --version
	if [[ "${output}" == "Docker version 1.13"* || "${output}" == "Docker version 17.03"* ]]; then
		skip
	fi

	start_docker_with_busybox 2
	swarm_manage

	# run
	docker_swarm run -d -e constraint:node==node-0 busybox sleep 100

	run docker_swarm network inspect bridge
	[ "$status" -ne 0 ]

	run docker_swarm network inspect node-0/bridge
	[[ "${output}" != *"\"Containers\": {}"* ]]

	run docker_swarm network inspect node-0/bridge
	echo "FIRSTINSPECT $output"

	run docker -H ${HOSTS[0]} network inspect bridge
	echo "SECONDINSPECT $output"

	diff <(docker_swarm network inspect node-0/bridge) <(docker -H ${HOSTS[0]} network inspect bridge)
}

@test "docker network create" {
	start_docker 2
	swarm_manage

	run docker_swarm network ls
	[ "${#lines[@]}" -eq 7 ]

	docker_swarm network create -d bridge test1
	run docker_swarm network ls
	[ "${#lines[@]}" -eq 8 ]

	docker_swarm network create -d bridge node-1/test2
	run docker_swarm network ls
	[ "${#lines[@]}" -eq 9 ]

	run docker_swarm network create -d bridge node-2/test3
	[ "$status" -ne 0 ]
}

@test "docker network rm" {
	start_docker_with_busybox 2
	swarm_manage

	run docker_swarm network rm test_network
	[ "$status" -ne 0 ]

	run docker_swarm network rm bridge
	[ "$status" -ne 0 ]

	docker_swarm network create -d bridge node-0/test
	run docker_swarm network ls
	[ "${#lines[@]}" -eq 8 ]

	docker_swarm network rm node-0/test
	run docker_swarm network ls
	[ "${#lines[@]}" -eq 7 ]
}

@test "docker network disconnect connect" {
	start_docker_with_busybox 2
	swarm_manage

	# run
	docker_swarm run -d --name test_container -e constraint:node==node-0 busybox sleep 100

	run docker_swarm network inspect node-0/bridge
	[[ "${output}" != *"\"Containers\": {}"* ]]

	docker_swarm network disconnect node-0/bridge test_container

	run docker_swarm network inspect node-0/bridge
	[[ "${output}" == *"\"Containers\": {}"* ]]

	docker_swarm network connect node-0/bridge test_container

	run docker_swarm network inspect node-0/bridge
	[[ "${output}" != *"\"Containers\": {}"* ]]

	docker_swarm rm -f test_container

	run docker_swarm network inspect node-0/bridge
	[[ "${output}" == *"\"Containers\": {}"* ]]
}

@test "docker network connect --ip" {
	start_docker_with_busybox 1
	swarm_manage

	docker_swarm network create -d bridge --subnet 10.0.0.0/24 testn

	run docker_swarm network inspect testn
	[[ "${output}" == *"\"Containers\": {}"* ]]

	# run
	docker_swarm run -d --name test_container  busybox sleep 100

	docker_swarm network connect --ip 10.0.0.42 testn test_container

	run docker_swarm inspect test_container
	[[ "${output}" == *"10.0.0.42"* ]]

	run docker_swarm network inspect testn
	[[ "${output}" != *"\"Containers\": {}"* ]]
}

@test "docker network connect --alias" {
	start_docker_with_busybox 1
	swarm_manage

	docker_swarm network create -d bridge testn

	run docker_swarm network inspect testn
	[[ "${output}" == *"\"Containers\": {}"* ]]

	# run
	docker_swarm run -d --name test_container  busybox sleep 100

	docker_swarm network connect --alias testa testn test_container

	run docker_swarm inspect test_container
	[[ "${output}" == *"testa"* ]]

	run docker_swarm network inspect testn
	[[ "${output}" != *"\"Containers\": {}"* ]]
}

@test "docker run --net <node>/<network>" {
	start_docker_with_busybox 2
	swarm_manage

	docker_swarm network create -d bridge node-1/testn

	docker_swarm run -d --net node-1/testn --name test_container busybox sleep 100

	run docker_swarm network inspect testn
	[[ "${output}" != *"\"Containers\": {}"* ]]
}
