NCOMPUTES ?= 2
PXEBOOT_ISO := ipxe.iso

cluster:
	@wget -O ${PXEBOOT_ISO} -c https://boot.ipxe.org/ipxe.iso
	@echo "Building a cluster with $(NCOMPUTES) compute nodes..."
	@mkdir cluster
	@./build-cluster.sh "$(NCOMPUTES)" "$(PXEBOOT_ISO)"

clean:
	@if [ -d cluster ]; then cd cluster; vagrant destroy -f; fi
	@rm -rf cluster

.PHONY: clean
