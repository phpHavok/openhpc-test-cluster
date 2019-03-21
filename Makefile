NCOMPUTES ?= 2

cluster:
	@echo "Building a cluster with $(NCOMPUTES) compute nodes..."
	@mkdir cluster
	@./build-cluster.sh "$(NCOMPUTES)"

clean:
	@if [ -d cluster ]; then cd cluster; vagrant destroy -f; fi
	@rm -rf cluster

.PHONY: clean
