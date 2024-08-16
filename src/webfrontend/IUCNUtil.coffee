class ez5.IUCNUtil

	@LINK_FIELD_SEPARATOR = ":__link:" # The link separator is used to separate iucn fields from their linked fields.

	@getFieldType: ->
		return "custom:base.custom-data-type-iucn.iucn"

	@getAssessmentData: (plugin_endpoint, assessment_id) ->
		return ez5.IUCNUtil.getFromPlugin("/assessment/" + assessment_id)

	@searchByTaxonname: (plugin_endpoint, genus, species) ->
		return ez5.IUCNUtil.getFromPlugin("/taxa/scientific_name?genus_name=" + encodeURIComponent(genus) + "&species_name=" + encodeURIComponent(species))

	@searchBySisTaxonId: (plugin_endpoint, sis_taxon_id) ->
		return ez5.IUCNUtil.getFromPlugin("/taxa/sis/" + sis_taxon_id)

	@getFromPlugin: (iucn_query) ->
		xhr = new CUI.XHR
			method: "GET"
			url: ez5.IUCNUtil.getPluginEndpoint()
			headers:
				# for simplification: include authorization for easydb5 and fylr
				# this causes no problems and the servers will use the correct one
				"authorization": 'Bearer ' + ez5.session.token
				"x-easydb-token": ez5.session.token
			url_data:
				iucn_query: iucn_query
		return xhr.start()

	@setObjectData: (object, data) ->
		# When data is empty, clean the object
		if CUI.util.isEmpty(data)
			delete object.idTaxon
			delete object.scientificName
			delete object.mainCommonName
			delete object.category
			delete object.redList
			return

		if CUI.util.isArray(data)
			data = data[0]

		object.redList = false
		object.category = ""
		object.mainCommonName = ""
		object.scientificName = data.scientific_name

		if not data.sis_taxon_id # taxon id not found
			return object

		object.idTaxon = "#{data.sis_taxon_id}"

		if not data.taxon # taxon data not found
			return object

		object.scientificName = data.taxon.scientific_name or ""

		if data.red_list_category.code
			object.category = data.red_list_category.code
			object.redList  = data.red_list_category.code in ["EX", "EW", "CR", "EN", "VU"]

		if not data.taxon.common_names
			return object
		if not CUI.util.isArray(data.taxon.common_names)
			return object
		for n in data.taxon.common_names
			if not n.main
				continue
			if not n.name
				continue
			object.mainCommonName = n.name
			break

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

	@getSettings: ->
		return ez5.session.getBaseConfig("plugin", "custom-data-type-iucn").iucn_settings

	@getPluginEndpoint: ->
		# return the url + endpoint to call the internal proxy that performs requests against the iucn api
		return ez5.pluginManager.getPlugin('custom-data-type-iucn')?.__plugin_url + "/proxy_api_v4"

	@getLatestAssessmentIdFromSearchResult: (data) ->
		deferred = new CUI.Deferred()
		if not data
			return {}

		# parse result, find id of latest assessment
		if not data.assessments
			return {}
		if not CUI.util.isArray(data.assessments)
			return {}

		for a in data.assessments
			if not a.latest
				continue
			if not a.assessment_id
				continue
			return a.assessment_id

		return 0