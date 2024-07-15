RUNTIME ?= podman
DISK ?= vda
RHCOS_VERSION ?= 4.16
IMAGE_SUFFIX ?=

BASE ?= registry.redhat.io/rhel9/rhel-bootc:9.4
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= qor-image/image
TAG ?= latest
IMAGE = $(REGISTRY)/$(REPOSITORY):$(TAG)

.PHONY: all
all: .push

overlays/users/usr/local/ssh/core.keys:
	@echo Please put the authorized_keys file you would like for the core user in $@ >&2
	@exit 1

overlays/auth/etc/ostree/auth.json:
	@if [ -e "$@" ]; then touch "$@"; else echo "Please put the auth.json for your registry $(REGISTRY)/$(REPOSITORY) in $@"; exit 1; fi

overlays/qor/usr/local/lib/qor/qor-0.5.1.3-1.el9.x86_64.rpm:
	@echo Please put the QOR RPM in $@ >&2
	@exit 1

.build: Containerfile overlays/qor/usr/local/lib/qor/qor-0.5.1.3-1.el9.x86_64.rpm overlays/auth/etc/ostree/auth.json $(shell git ls-files | grep '^overlays/') overlays/users/usr/local/ssh/core.keys
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=newer --from $(BASE) . -t $(IMAGE)
	@touch $@

.PHONY: build
build: .build

.push: .build
	$(RUNTIME) push $(IMAGE)
	@touch $@

.PHONY: push
push: .push

boot-image/rhcos-live.x86_64.iso:
	curl -Lo $@ https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$(RHCOS_VERSION)/latest/rhcos-live.x86_64.iso

.base:
	$(RUNTIME) pull --arch amd64 $(BASE)
	$(RUNTIME) push --remove-signatures $(BASE) $(REGISTRY)/$(REPOSITORY):base
	touch .base

boot-image/bootc$(IMAGE_SUFFIX).btn: boot-image/bootc.btn.tpl overlays/auth/etc/ostree/auth.json
	IMAGE=$(IMAGE)$(IMAGE_SUFFIX) AUTH='$(strip $(file < overlays/auth/etc/ostree/auth.json))' DISK=$(DISK) envsubst '$$IMAGE,$$AUTH,$$DISK' < $< >$@

boot-image/bootc$(IMAGE_SUFFIX).ign: boot-image/bootc$(IMAGE_SUFFIX).btn
	$(RUNTIME) run --rm -i quay.io/coreos/butane:release --pretty --strict < $< >$@

boot-image/qor-bootc-rhcos$(IMAGE_SUFFIX).iso: boot-image/bootc$(IMAGE_SUFFIX).ign boot-image/rhcos-live.x86_64.iso
	@if [ -e $@ ]; then rm -f $@; fi
	$(RUNTIME) run --rm --arch amd64 --security-opt label=disable --pull=newer -v ./:/data -w /data \
    	quay.io/coreos/coreos-installer:release iso customize --live-ignition=./$< \
    	-o $@ boot-image/rhcos-live.x86_64.iso

.PHONY: iso
iso: boot-image/qor-bootc-rhcos$(IMAGE_SUFFIX).iso

.PHONY: burn
burn: iso
	sudo dd if=./$< of=$(ISO_DEST) bs=1M conv=fsync status=progress

.PHONY: debug
debug:
	$(RUNTIME) run --rm -it --arch amd64 --pull=never --entrypoint /bin/bash $(IMAGE) -li

.PHONY: update
update:
	$(RUNTIME) build --security-opt label=disable --arch amd64 --pull=newer --from $(IMAGE) -f Containerfile.update . -t $(IMAGE)
	$(RUNTIME) push $(IMAGE)

.PHONY: clean
clean:
	rm -rf .build .push boot-image/*.iso boot-image/*.btn boot-image/*.ign
	buildah prune -f
