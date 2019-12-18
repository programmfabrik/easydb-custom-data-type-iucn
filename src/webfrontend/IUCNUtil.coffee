class ez5.IUCNUtil

	@ENDPOINT_SPECIES = "/species/"

	@searchBySpecies: (species) ->
		apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + ez5.IUCNUtil.ENDPOINT_SPECIES + species + "?token=" + apiSettings.api_token
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