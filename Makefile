PLUGIN_NAME = custom-data-type-iucn
PLUGIN_PATH = easydb-custom-data-type-iucn

EASYDB_LIB = easydb-library

L10N_FILES = l10n/$(PLUGIN_NAME).csv
L10N_GOOGLE_KEY = 1Z3UPJ6XqLBp-P8SUf-ewq4osNJ3iZWKJB83tc6Wrfn0
L10N_GOOGLE_GID = 1058658585

INSTALL_FILES = \
	$(WEB)/l10n/cultures.json \
	$(WEB)/l10n/de-DE.json \
	$(WEB)/l10n/en-US.json \
	$(WEB)/l10n/es-ES.json \
	$(WEB)/l10n/it-IT.json \
	$(WEB)/image/logo.png \
	build/scripts/iucn-update.js \
	$(CSS) \
	$(JS) \
	manifest.yml

COFFEE_FILES = src/webfrontend/IUCNUtil.coffee \
	src/webfrontend/CustomDataTypeIUCN.coffee \
	src/webfrontend/CustomBaseConfigIUCN.coffee

all: build

SCSS_FILES = src/webfrontend/scss/custom-data-type-iucn.scss

COPY_LOGO = $(WEB)/image/logo.png
$(WEB)/image%:
	cp -f $< $@

# Order of files is important.
UPDATE_SCRIPT_COFFEE_FILES = \
	src/webfrontend/IUCNUtil.coffee \
	src/script/IUCNUpdate.coffee
UPDATE_SCRIPT_BUILD_FILE = build/scripts/iucn-update.js

${UPDATE_SCRIPT_BUILD_FILE}: $(subst .coffee,.coffee.js,${UPDATE_SCRIPT_COFFEE_FILES})
	mkdir -p $(dir $@)
	cat $^ > $@

include $(EASYDB_LIB)/tools/base-plugins.make
build: code $(L10N) $(COPY_LOGO) $(UPDATE_SCRIPT_BUILD_FILE) buildinfojson

code: $(JS) css

clean: clean-base

wipe: wipe-base
