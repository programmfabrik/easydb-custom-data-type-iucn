class IUCNUpdate

	# Returns the base easydb URL.
	__getEasydbUrl: (data) ->
		# TODO: Check where the url of easydb is provided. Probably in data.server_config?
		return "http://localhost/api/v1"

	__startUpdate: (data) ->
		# TODO: Do a validation for the token configured in the database.
		# I found that the response of the API returns 200 - 'message': "Token not valid!" if it is wrong (not error)
		@__login(data).done((response) =>
			ez5.respondSuccess(
				# The fetch of the schema could be here as well, but maybe it is not a good idea because it is big.
				state: easydbToken: response.token
			)
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
			@__updateTags(objectsToUpdateTags).done(=>
				ez5.respondSuccess({payload: objectsToUpdate})
			) # TODO: When the update fails, update objects anyways?
		)

	__updateTags: (objects) ->
		return CUI.chunkWork.call(@,
			items: objects
			chunk_size: 1
			call: (items) =>
				#TODO: Implement the search and the update of tags.
		)

	main: (data) ->
		if not data
			ez5.respondError("custom.data.type.iucn.update.error.payload-missing")
			return

		for key in ["action", "server_config", "plugin_config"]
			if (!data[key])
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