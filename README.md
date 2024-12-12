# easydb-custom-data-type-iucn Plugin

Custom Data Type "IUCN" for easydb

This is a plugin for easyDB 5 which provides a custom data type "IUCN" for references to the IUCN Red List of Threatened Species [*(IUCN 2024. IUCN Red List of Threatened Species. Version 2024-2 <www.iucnredlist.org>)*](https://www.iucnredlist.org/). This is an external repository managed by the *International Union for Conservation of Nature and Natural Resources*


## Scope and Limitations

The plugin only reads and displays data from this repository. The content which is displayed in easydb5 is completly dependant on the content of the external repository.

The plugin connects to the [API version 4](https://api.iucnredlist.org/api-docs/index.html). The functionality of the plugin is limited by the functionality of this API. External changes in the API can happen at any time, which would affect the plugin.

The plugin provides a search functionality in the editor in the frontend (see [below](#adding-entries-from-the-repository)), and a background update process which is run by the [Custom Data Type Updater](https://docs.easydb.de/en/technical/plugins/customdatatype/customdatatype_updater/). This update process collects existing records with entries of this custom data type, and updates these records if there have been any changes in the external repository.

Also, this update process can add / remove a "Red List" tag to records where this custom data type is linked. This tag must be configured in easydb5 (see [below](#red-list-tag)). This tag indicates whether the species which is referenced in the custom data type is on the red list.


## Configuration

The plugin must be configured in the easydb5 [base configuration](https://docs.easydb.de/en/webfrontend/administration/base-config/#basic-configuration) under the category "IUCN".


### API settings

The plugin connects to the IUCN API, which requires authentication with an API token.

* the "URL" has the default value `https://api.iucnredlist.org/api/v4`, this should not be changed.
* the "Token" must be requested and entered here. For more information see [API Usage: https://api.iucnredlist.org/](https://api.iucnredlist.org/).


### "Red List" Tag

The tag which is used as the "Red List" tag must be configured in the [tag manager](https://docs.easydb.de/en/webfrontend/rightsmanagement/tags/#tags). It can be named and configured in any way, and later must be selected in the base configuration under "Settings" -> "Red list tag".

Multiple fields in different objecttypes can be selected under "Settings" -> "IUCN Fields". These fields are considered by the plugin to decide if the tag should be added / removed to the record. Only fields in records, for which tag management is enabled in the datamodel, are available here.

*Please note*: this feature is optional, selecting a tag or fields is not necessary. Searching and displaying references to the IUCN repository in records is not affected by these settings.


### easydb settings

The plugin internally uses the easydb5 API. This requires an API user with the necessary rights. Enter "Username" and "Password" of the user. Add this user to easydb5 (see ["Rights Management" -> "User"](https://docs.easydb.de/en/webfrontend/rightsmanagement/users/)), and setup the necessary rights for this user (see ["Rights Management"](https://docs.easydb.de/en/webfrontend/rightsmanagement/)).

The API user needs at least "View & Edit Records" and "Allowed Masks" rights for all objecttypes for which tags should be added / removed.


### Update settings

The custom datatype updater runs at a fixed time daily, and for each custom datatype a delay in days can be configured. During these days, the custom datatype is not considered for updates.

To define the delay in days for this custom datatype, open the "Custom Data Type Updater" page in the base configuration. Under "IUCN Updater" -> "Days between updates" enter a number. `1` means the custom datatypes are updated daily, `7` would mean an update every week.


## Adding entries from the repository

In the frontend editor select a field with this custom data type and search for a repository entry:


### Searching by SIS ID

If the entered search term is numerical, the plugin treats it as a *SIS ID* and tries to find the record using the `/api/v4/taxa/sis/` endpoint.


### Searching by genus and species

To search a species by name, the *latin binomal nomenclature* must be entered. It must consist of the genus name and species name, for example "Canis lupus".

The plugin tries to find the record using the `/api/v4/taxa/scientific_name
` endpoint.
