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
		apiSettings = data.server_config.iucn_api_settings

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
		if objects.length == 0
			return CUI.resolvedPromise()

		iucnSettings = data.server_config.iucn_settings
		if not iucnSettings
			return CUI.resolvedPromise() # TODO: Error or skip?

		idTagRed = iucnSettings.tag_red
		idTagUnclear = iucnSettings.tag_unclear
		iucnFields = iucnSettings.iucn_fields

		if not iucnFields or not idTagRed or not idTagUnclear
			return CUI.resolvedPromise() # TODO: Error or skip?

		easydbToken = data.state.easydbToken
		if not easydbToken
			return CUI.resolvedPromise() # TODO: this should not happen, but if the token is not in the state, what to do?

		fields = iucnFields.map((field) -> field.iucn_field_name + ".idTaxon")
		objecttypes = fields.map((fieldFullName) -> fieldFullName.split(".")[0])
		easydbUrl = @__getEasydbUrl(data)

		return CUI.chunkWork.call(@,
			items: objects
			chunk_size: 1
			call: (items) =>
				deferred = new CUI.Deferred()

				item = items[0]
				xhr = new CUI.XHR
					method: "POST"
					url: easydbUrl + "/search"
					headers:
						'x-easydb-token' : easydbToken
					body:
						offset: 0,
						limit: 1000, # TODO: Recursive to get all? something like search_no_limit
						search: [
							type: "in",
							fields: fields,
							in: [item.data.idTaxon],
							bool: "must"
						],
						format: "long",
						objecttypes: objecttypes
				xhr.start().done((response) =>
					if not response.objects or response.objects.length == 0
						deferred.resolve()
						return

					objectsByObjecttype = {}
					response.objects.forEach((object) =>
						objecttype = object._objecttype
						if not objectsByObjecttype[objecttype]
							objectsByObjecttype[objecttype] = []

						if not object._tags
							object._tags = []

						# TODO: Check the correct behaviour for red/unclear tag.
						if item.data.redList
							idTagToSet = idTagRed
						else
							idTagToSet = idTagUnclear

						if object._tags.some((tag) -> tag._id == idTagToSet)
							return # Tag is set, we skip the object.

						object._tags.push(_id: idTagToSet)
						object[objecttype]._version++
						objectsByObjecttype[objecttype].push(object)
					)

					updatePromises = []
					for objecttype, _objects of objectsByObjecttype
						xhr = new CUI.XHR
							method: "POST"
							url: easydbUrl + "/db/#{objecttype}"
							headers:
								'x-easydb-token' : easydbToken
							body: _objects
						updatePromises.push(xhr.start())

					CUI.whenAll(updatePromises).done( =>
						deferred.resolve()
					).fail(=>
						# TODO: Skip or error?
						deferred.resolve()
					)
				).fail((a)=>
					# TODO: Skip or error?
					deferred.resolve()
				)

				return deferred.promise()
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