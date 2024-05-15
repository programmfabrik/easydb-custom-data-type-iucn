class ez5.IUCNUtil

	@ENDPOINT_SPECIES = "/species/"
	@ENDPOINT_SPECIES_ID = "/species/id/"
	@LINK_FIELD_SEPARATOR = ":__link:" # The link separator is used to separate iucn fields from their linked fields.

	@getFieldType: ->
		return "custom:base.custom-data-type-iucn.iucn"

	@searchBySpecies: (species, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + ez5.IUCNUtil.ENDPOINT_SPECIES + encodeURIComponent(species) + "?token=" + apiSettings.api_token
		return ez5.IUCNUtil.get(url)

	@searchBySpeciesId: (id, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + ez5.IUCNUtil.ENDPOINT_SPECIES_ID + id + "?token=" + apiSettings.api_token
		return ez5.IUCNUtil.get(url)

	@get: (url) ->
		xhr = new CUI.XHR
			method: "GET"
			url: url
		return xhr.start()

	@setObjectData: (object, data) ->
		if CUI.util.isEmpty(data) # When data is empty, clean the object.
			delete object.idTaxon
			delete object.scientificName
			delete object.mainCommonName
			delete object.category
			delete object.redList
			return

		object.redList = false

		if CUI.util.isArray(data)
			data = data[0]

		if not data.taxonid # Not found
			object.scientificName = data.scientific_name
			return object

		object.redList = data.category in ["EX", "EW", "CR", "EN", "VU"]

		object.idTaxon = "#{data.taxonid}"
		object.scientificName = data.scientific_name or ""
		object.mainCommonName = data.main_common_name or ""
		object.category = data.category
		return object

	@isEqual: (objectOne, objectTwo) ->
		for key in ["idTaxon", "scientificName", "mainCommonName", "category", "redList"]
			if not CUI.util.isEqual(objectOne[key], objectTwo[key])
				return false
		return true

	@getSaveData: (data) ->
		saveData =
			idTaxon: data.idTaxon
			scientificName: data.scientificName
			mainCommonName: data.mainCommonName
			category: data.category
			redList: data.redList
			_fulltext:
				text: "#{data.scientificName} #{data.mainCommonName}"
				string: "#{data.idTaxon}"
			_standard:
				text: data.scientificName
		return saveData

	@getApiSettings: ->
		return ez5.session.getBaseConfig("plugin", "custom-data-type-iucn").iucn_api_settings

	@getSettings: ->
		return ez5.session.getBaseConfig("plugin", "custom-data-type-iucn").iucn_settings