SHELL := /usr/bin/env bash

INDEX ?= index.json
KEY ?= keys/teanode-sources-ed25519-private.pem
PUB ?= keys/teanode-sources-ed25519-public.pem
KEY_DIR ?= keys
KEY_NAME ?= teanode-sources

.PHONY: help keygen pubkey hash sign sign-out verify

help:
	@echo "Targets:"
	@echo "  make keygen                 # generate Ed25519 keypair into $(KEY_DIR)/"
	@echo "  make pubkey                 # print base64 public key for TeaNode config"
	@echo "  make hash                   # update sha256 hashes in $(INDEX) from local source files"
	@echo "  make sign                   # update hashes then sign $(INDEX) in place using $(KEY)"
	@echo "  make sign-out OUT=...       # sign to output file"
	@echo "  make verify                 # verify signatures in $(INDEX) using $(PUB)"

keygen:
	scripts/generate-key.sh "$(KEY_DIR)" "$(KEY_NAME)"

pubkey:
	scripts/sign-index.sh --key "$(KEY)" --print-public-key

hash:
	@COUNT=$$(jq '.sources | length' "$(INDEX)"); \
	TMP=$$(mktemp); \
	cp "$(INDEX)" "$$TMP"; \
	for i in $$(seq 0 $$((COUNT - 1))); do \
		NAME=$$(jq -r ".sources[$$i].name" "$$TMP"); \
		FILE="sources/$$NAME/source.md"; \
		if [ ! -f "$$FILE" ]; then \
			echo "source file not found: $$FILE" >&2; \
			rm -f "$$TMP"; \
			exit 1; \
		fi; \
		HASH=$$(sha256sum "$$FILE" | cut -d' ' -f1); \
		UPDATED=$$(mktemp); \
		jq ".sources[$$i].sha256 = \"$$HASH\"" "$$TMP" > "$$UPDATED"; \
		mv "$$UPDATED" "$$TMP"; \
		echo "$$NAME: $$HASH"; \
	done; \
	mv "$$TMP" "$(INDEX)"

sign: hash
	scripts/sign-index.sh --key "$(KEY)" --index "$(INDEX)" --in-place

sign-out:
	@test -n "$(OUT)" || (echo "OUT is required, e.g. make sign-out OUT=index.signed.json" >&2; exit 1)
	scripts/sign-index.sh --key "$(KEY)" --index "$(INDEX)" --output "$(OUT)"

verify:
	scripts/verify-index.sh --public-key-file "$(PUB)" --index "$(INDEX)"
