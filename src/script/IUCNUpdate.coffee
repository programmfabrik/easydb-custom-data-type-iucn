class IUCNUpdate

	# Returns the base easydb URL.
	__getEasydbUrl: (data) ->
		# TODO: Check where the url of easydb is provided. Probably in data.server_config?
		return "http://localhost/api/v1"

	__startUpdate: (data) ->
		# TODO: Do a validation for the token configured in the database.
		# I found that the response of the API returns 200 - 'message': "Token not valid!" if it is wrong (not error)
		@__login(data).done((response) =>
			easydbToken = response.token
			if not easydbToken
				ez5.respondError("custom.data.type.iucn.start-update.error.easydb-token-empty")
				return

			systemConfig = response?.config?.base?.system
			if not systemConfig
				ez5.respondError("custom.data.type.iucn.start-update.error.system-config-empty")
				return

			state =
				easydbToken: easydbToken
				config: {}

			# TODO: Maybe it is not necessary to save more stuff than the token in the state because it could be included
			# in the update request.
			for settingsKey in ["iucn_settings", "iucn_easydb_settings", "iucn_api_settings"]
				if not systemConfig[settingsKey]
					ez5.respondError("custom.data.type.iucn.start-update.error.#{settingsKey}-empty")
					return
				state.config[settingsKey] = systemConfig[settingsKey]

			ez5.respondSuccess(state: state)
		).fail((error) =>
			ez5.respondError("custom.data.type.iucn.start-update.error.login", error: error.response?.data or error)
		)
		return

	__login: (data) ->
		# TODO: Check the correct path for settings.
		serverConfig = data.server_config
		login = serverConfig.iucn_easydb_settings?.easydb_login
		password = serverConfig.iucn_easydb_settings?.easydb_password

		if not login or not password
			ez5.respondError("custom.data.type.iucn.start-update.error.login-password-not-provided",
				login: login
				password: password
			)
			return
		deferred = new CUI.Deferred()

		easydbUrl = @__getEasydbUrl(data)
		# Get session, to get a valid token.
		xhr = new CUI.XHR
			method: "GET"
			url: "#{easydbUrl}/session" # TODO: Perhaps it is necessary to store some base config settings in the state of this response.
		xhr.start().done((response) =>
			# Authentication with login and password.
			xhr = new CUI.XHR
				method: "POST"
				url: "#{easydbUrl}/session/authenticate?login=#{login}&password=#{password}"
				headers:
					'x-easydb-token' : response.token
			xhr.start().done(deferred.resolve).fail(deferred.reject)
		).fail(deferred.reject)
		return deferred.promise()

	__getSchema: (data) ->
		{easydbToken} = data.state

		url = @__getEasydbUrl(data) + "/schema/user/CURRENT?format=json"
		xhr = new CUI.XHR
			method: "GET"
			url: url
			headers:
				'x-easydb-token' : easydbToken
		return xhr.start()

	__update: (data) ->
		@__getSchema(data).done((schema) =>
			@__updateObjects(data, schema)
		).fail((error) =>
			ez5.respondError("custom.data.type.iucn.start-update.error.get-schema", error: error.response?.data or error)
		)

	__updateObjects: (data, schema) ->
		apiSettings = data.server_config.iucn_api_settings # TODO: Check where to get the settings.
		# Some objects will contain the ID and it is necessary to make the search by id, otherwise they will contain the
		# scientific name.
		objectsByIdMap= {}
		objectsByNameMap= {}

		for object in data.objects
			if not (object.identifier and object.data)
				continue

			if not object.data.idTaxon and not object.data.scientificName
				continue

			if object.data.idTaxon
				idTaxon = object.data.idTaxon
				if not objectsByIdMap[idTaxon]
					objectsByIdMap[idTaxon] = []
				objectsByIdMap[idTaxon].push(object)
			else
				scientificName = object.data.scientificName
				if not objectsByNameMap[scientificName]
					objectsByNameMap[scientificName] = []
				objectsByNameMap[scientificName].push(object)

		objectsToUpdate = []
		objectsToUpdateTags = []

		chunkByName = CUI.chunkWork.call(@,
			items: Object.keys(objectsByNameMap)
			chunk_size: 1
			call: (items) =>
				scientificName = items[0]
				ez5.IUCNUtil.searchBySpecies(scientificName, apiSettings).done((response) =>
					objectFound = response.result?[0]
					if not objectFound
						return
					foundData = ez5.IUCNUtil.setObjectData({}, objectFound)
					for object in objectsByNameMap[scientificName]
						object.data = ez5.IUCNUtil.getSaveData(foundData)
						# Object is updated now. Next time that the script is executed with this object
						# the tags of the top level object will be updated.
						object.data.__updateTags = true
						objectsToUpdate.push(object)
					return
				)
		)

		chunkById = CUI.chunkWork.call(@,
			items: Object.keys(objectsByIdMap)
			chunk_size: 1
			call: (items) =>
				id = items[0]
				ez5.IUCNUtil.searchBySpeciesId(id, apiSettings).done((response) =>
					objectFound = response.result?[0]
					if not objectFound
						return
					foundData = ez5.IUCNUtil.setObjectData({}, objectFound)
					for object in objectsByIdMap[id]
						if ez5.IUCNUtil.isEqual(object.data, foundData)
							# If the data did not change since the last time it was checked, and the __updateTags is true.
							if object.data.__updateTags
								delete object.data.__updateTags
								objectsToUpdateTags.push(object)
						else
							object.data = ez5.IUCNUtil.getSaveData(foundData)
							object.data.__updateTags = true
							objectsToUpdate.push(object)
					return
				)
		)

		CUI.whenAll([chunkByName, chunkById]).done( =>
			@__updateTags(objectsToUpdateTags, schema, data).done(=>
				ez5.respondSuccess({payload: objectsToUpdate})
			).fail((messageKey) =>
				# TODO: When the update fails, update objects anyways? or error?
				ez5.respondError(messageKey)
			)
		)

	__updateTags: (objects, schema, data) ->
		objecttypes = data.server_config.iucn_settings?.objecttypes
		if not objecttypes
			return CUI.resolvedPromise() # No objects will be updated. #TODO: Show error instead?

		iucnType = ez5.IUCNUtil.getFieldType()

		tablesById = {}
		for table in schema.tables
			tablesById[table.table_id] = table

		# data.server_config.iucn_settings.objecttypes (array)
		# objecttype_direct is the id of the ot that contains a field of iucn custom data type
		# objecttype_with_link is the id of the ot that contains objecttype_direct as linked object.

		for objecttype in data.server_config.iucn_settings.objecttypes
			# Table with IUCN columns.
			tableDirect = tablesById[objecttype.objecttype_direct]
			# Table with links to tableDirect.
			tableLink = tablesById[objecttype.objecttype_with_link]

			if not tableDirect?.columns # Table does not exist.
				continue

			# TODO: Perhaps instead of saving the columns, it would be nice to build the search request
			# and keep a map with the references to the values to change then dinamically afterwards in the chunk work.
			# Or just move everything to a method and re-use it with every value.
			# Or build an structure prepared to generate the search easily.
			columns = []
			for column in tableDirect.columns
				if not column.type == iucnType
					continue

				if column.kind == "link" and tablesById[column.other_table_id] # Nested field.
					nestedTable = tablesById[column.other_table_id]
#					nestedTable.columns # TODO: How many levels of nested?

					# TODO: If nested does not contain a column, skip as well.
					continue

				columns.push(column)

			if columns.length == 0 # No IUCN columns found.
				continue

			if not tableLink?.foreign_keys
				continue

			for foreignKey in tableLink.foreign_keys
				if not tableLink.columns or foreignKey.referenced_table?.table_id != tableDirect.table_id
					continue

				column = tableLink.columns.find((column) -> column.column_id == foreignKey.columns[0].column_id)
				if not column or column.type != "link"
					continue

				# Linked table found in the 'column'.
				# column is the field where the linked object to the direct table is.
				# TODO: add the search.
				# I think it should be a second search, where it searches for results of the previous one.


		return CUI.chunkWork.call(@,
			items: objects
			chunk_size: 1
			call: (items) =>
				#TODO: Implement the search and the update of tags.
				item = items[0]

				# Example of item
				#				"identifier": "1",
				#				"data": {
				#					"idTaxon": 12392,
				#					"scientificName": "Loxodonta africana",
				#					"mainCommonName": "African Elephant",
				#					"redList": true,
				#					"_fulltext": {
				#						"text": "Loxodonta africana African Elephant",
				#						"string": "12392"
				#					},
				#					"_standard": {
				#						"text": "Loxodonta africana"
				#					},
				#					"__updateTags": true
				#				}

				# It is necessary to search objects that contains objects with the same idTaxon in the fields specified in the config
				# How to search when the field is a custom data type? Maybe use the standard and save the id in the _standard?
				# (atm the standard contains the scientific name)


		)

	main: (data) ->
		if not data
			ez5.respondError("custom.data.type.iucn.update.error.payload-missing")
			return

		for key in ["action", "plugin_config", "server_config"]
			if (not data[key])
				ez5.respondError("custom.data.type.iucn.update.error.payload-key-missing", {key: key})
				return

		if (data.action == "start_update")
			@__startUpdate(data)
			return

		else if (data.action == "update")
			if (!data.objects)
				ez5.respondError("custom.data.type.iucn.update.error.objects-missing")
				return

			if (!(data.objects instanceof Array))
				ez5.respondError("custom.data.type.iucn.update.error.objects-not-array")
				return

			if (!data.state)
				ez5.respondError("custom.data.type.gazeteer.update.error.state-missing")
				return

			@__update(data)
			return
		else
			ez5.respondError("custom.data.type.iucn.update.error.invalid-action", action: data.action)
		return

module.exports = new IUCNUpdate()