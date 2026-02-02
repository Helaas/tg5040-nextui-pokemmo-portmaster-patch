STAGED_DIR := staged
PAKZ_NAME := pokemmo_patch.pakz
# Path relative to /mnt/SDCARD where the files should be extracted
DEST_PREFIX := Roms/Ports (PORTS)/.ports/pokemmo
PORTS_PREFIX := Roms/Ports (PORTS)/.ports
ROMS_PREFIX := Roms/Ports (PORTS)

.PHONY: pakz clean

pakz: $(PAKZ_NAME)

$(PAKZ_NAME): $(shell find $(STAGED_DIR) -type f -not -name '.DS_Store') post_install.sh
	@rm -f "$@"
	@mkdir -p /tmp/pokemmo_zip_staging
	@rm -rf "/tmp/pokemmo_zip_staging/$(DEST_PREFIX)"
	@mkdir -p "/tmp/pokemmo_zip_staging/$(DEST_PREFIX)"
	@rsync -a --exclude='.DS_Store' $(STAGED_DIR)/ "/tmp/pokemmo_zip_staging/$(DEST_PREFIX)/"
	@cp "/tmp/pokemmo_zip_staging/$(DEST_PREFIX)/PokeMMO.sh" "/tmp/pokemmo_zip_staging/$(PORTS_PREFIX)/PokeMMO.sh"
	@cp "/tmp/pokemmo_zip_staging/$(DEST_PREFIX)/PokeMMO.sh" "/tmp/pokemmo_zip_staging/$(ROMS_PREFIX)/PokeMMO.sh"
	@cp post_install.sh /tmp/pokemmo_zip_staging/post_install.sh
	@cd /tmp/pokemmo_zip_staging && zip -r "$(CURDIR)/$@" . -x '*/.DS_Store'
	@rm -rf /tmp/pokemmo_zip_staging
	@echo "Created $@ ($(shell du -h "$@" 2>/dev/null | cut -f1 || echo '?'))"
	@echo "To apply: copy $@ to /mnt/SDCARD and reboot"

clean:
	rm -f $(PAKZ_NAME)
	rm -rf /tmp/pokemmo_zip_staging
