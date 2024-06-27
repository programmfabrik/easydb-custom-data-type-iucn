class ez5.IUCNUtil

	# xxx remove
	@ENDPOINT_SPECIES_PAGE = "/species/page/"

	@LINK_FIELD_SEPARATOR = ":__link:" # The link separator is used to separate iucn fields from their linked fields.

	@getFieldType: ->
		return "custom:base.custom-data-type-iucn.iucn"

	@getAssessmentData: (assessment_id, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + "/assessment/" + assessment_id
		# console.debug "getAssessmentData",assessment_id,"=>",url
		return ez5.IUCNUtil.get(url, apiSettings.api_token)

	@searchByTaxonname: (genus, species, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + "/taxa/scientific_name?genus_name=" + encodeURIComponent(genus) + "&species_name=" + encodeURIComponent(species)
		# console.debug "searchByTaxonname",genus,species,"=>",url
		return ez5.IUCNUtil.get(url, apiSettings.api_token)

	@searchBySisTaxonId: (sis_taxon_id, apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()
		url = apiSettings.api_url + "/taxa/sis/" + sis_taxon_id
		# console.debug "searchBySisTaxonId",sis_taxon_id,"=>",url
		return ez5.IUCNUtil.get(url, apiSettings.api_token)

	# xxx remove
	@fetchAllSpecies: (apiSettings) ->
		if not apiSettings
			apiSettings = ez5.IUCNUtil.getApiSettings()

		data = objects: []
		deferred = new CUI.Deferred()
		fetchPage = (page = 0) ->
			url = apiSettings.api_url + ez5.IUCNUtil.ENDPOINT_SPECIES_PAGE + page
			ez5.IUCNUtil.get(url, apiSettings.api_token).done((response) =>
				if not response or response.message
					return deferred.resolve(response)

				if response.count > 0
					data.objects = data.objects.concat(response.result)
					page++
					fetchPage(page)
				else
					deferred.resolve(data)
			).fail(deferred.reject)
		fetchPage()
		return deferred.promise()

	@get: (url, api_token) ->
		# todo CORS problems, because the "authorization" header is missing in OPTIONS request before GET
		xhr = new CUI.XHR
			method: "GET"
			url: url
			headers:
				"authorization": api_token
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

		if not data.taxonid # Not found # todo sis id?
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