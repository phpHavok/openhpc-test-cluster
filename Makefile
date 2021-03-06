NCOMPUTES ?= 2
PXEBOOT_ISO := ipxe.iso

cluster: $(PXEBOOT_ISO)
	@echo "Building a cluster with $(NCOMPUTES) compute nodes..."
	@mkdir cluster
	@./build-cluster.sh "$(NCOMPUTES)" "$(PXEBOOT_ISO)"

$(PXEBOOT_ISO):
	wget -O "$@" http://boot.ipxe.org/ipxe.iso

clean:
	@if [ -d cluster ]; then cd cluster; vagrant destroy -f; fi
	@rm -rf cluster

.PHONY: clean
