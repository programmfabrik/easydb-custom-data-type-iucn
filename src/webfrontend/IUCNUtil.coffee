class ez5.IUCNUtil

	@ENDPOINT_SPECIES = "/species/"
	@ENDPOINT_SPECIES_ID = "/species/id/"

	@searchBySpecies: (species, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + ez5.IUCNUtil.ENDPOINT_SPECIES + species + "?token=" + apiSettings.api_token
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
		object.idTaxon = data.taxonid
		object.scientificName = data.scientific_name
		object.mainCommonName = data.main_common_name
		object.redList = true # TODO: set true, false. for unclear maybe add a new attribute.
		return object

	@isEqual: (objectOne, objectTwo) ->
		for key in ["idTaxon", "scientificName", "mainCommonName", "redList"]
			if not CUI.util.isEqual(objectOne[key], objectTwo[key])
				return false
		return true

	@getSaveData: (data) ->
		saveData =
			idTaxon: data.idTaxon
			scientificName: data.scientificName
			mainCommonName: data.mainCommonName
			redList: data.redList
			_fulltext:
				text: "#{data.scientificName} #{data.mainCommonName}"
				string: "#{data.idTaxon}"
			_standard:
				text: data.scientificName
		return saveData

	@getApiSettings: ->
		return ez5.session.config.base.system.iucn_api_settings

	@getSettings: ->
		return ez5.session.config.base.system.iucn_settings