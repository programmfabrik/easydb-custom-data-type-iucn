class IUCNUpdate

	# Returns the base easydb URL.
	__getEasydbUrl: (data) ->
		# TODO: Check where the url of easydb is provided. Probably in data.server_config?
		return "http://localhost/api/v1"

	__startUpdate: (data) ->
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

			# TODO: FOR NOW ONLY THE EASYDB TOKEN IN THE STATE IS USED. CHECK IF THE IUCN CONFIGURATION WILL BE AVAILABLE IN
			# SYSTEM CONFIG IN THE UPDATE, OTHERWISE IT IS NECESSARY TO ADD IT TO THE STATE.
			for settingsKey in ["iucn_settings", "iucn_easydb_settings", "iucn_api_settings"]
				if not systemConfig[settingsKey]
					ez5.respondError("custom.data.type.iucn.start-update.error.#{settingsKey}-empty")
					return
#				state.config[settingsKey] = systemConfig[settingsKey]

			ez5.respondSuccess(state: state)
		).fail((error) =>
			ez5.respondError("custom.data.type.iucn.start-update.error.login", error: error?.response?.data or error)
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
			url: "#{easydbUrl}/session"
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

	# TODO: Remove schema if not used.
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
		# TODO: CHECK IF THE IUCN TOKEN IS VALID BEFORE DOING ANYTHING.
		# I found that the response of the API returns 200 - 'message': "Token not valid!" if it is wrong (not error)
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
					objectsFound = response.result
					if CUI.util.isEmpty(objectsFound)
						return
					foundData = ez5.IUCNUtil.setObjectData({}, objectsFound)
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
					objectsFound = response.result
					if CUI.util.isEmpty(objectsFound)
						return
					foundData = ez5.IUCNUtil.setObjectData({}, objectsFound)
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
			).fail((messageKey, opts = {}) =>
				ez5.respondError(messageKey, opts)
			)
		)

	__updateTags: (objects, schema, data) ->
		if objects.length == 0
			return CUI.resolvedPromise()

		iucnSettings = data.server_config.iucn_settings
		if not iucnSettings
			return CUI.rejectedPromise("custom.data.type.iucn.update.error.not-available-settings")

		idTagRed = iucnSettings.tag_red
		idTagUnclear = iucnSettings.tag_unclear
		iucnFields = iucnSettings.iucn_fields

		if not iucnFields or not idTagRed or not idTagUnclear
			return CUI.rejectedPromise("custom.data.type.iucn.update.error.not-available-settings")

		easydbToken = data.state.easydbToken
		if not easydbToken
			return CUI.rejectedPromise("custom.data.type.iucn.update.error.not-easydb-token-in-state")

		linkSeparator = ez5.IUCNUtil.LINK_FIELD_SEPARATOR

		linkedFields = [] # TODO: Implement.
		fields = []
		iucnFields.forEach((field) ->
			if field.iucn_field_name.indexOf(linkSeparator) != -1
				fieldName = field.iucn_field_name
				index = fieldName.indexOf(linkSeparator)
				linkedFields.push
					linked_field: fieldName.substring(0, index)
					field: fieldName.substring(index + linkSeparator.length)
			else
				fields.push(field.iucn_field_name + ".idTaxon")
		)
		objecttypes = fields.map((fieldFullName) -> fieldFullName.split(".")[0])
		easydbUrl = @__getEasydbUrl(data)

		return CUI.chunkWork.call(@,
			items: objects
			chunk_size: 1
			call: (items) =>
				deferred = new CUI.Deferred()

				item = items[0]

				addTagBody =
					_mask: "_all_fields"
					_tags: []
					_comment: "IUCN UPDATE - ADD TAG"
					"_tags:group_mode": "tag_add"

				removeTagBody =
					_mask: "_all_fields"
					_tags: []
					_comment: "IUCN UPDATE - REMOVE TAG"
					"_tags:group_mode": "tag_remove"

				# TODO: Check the correct behaviour for red/unclear tag.
				if item.data.redList
					addTagBody._tags.push(_id: idTagRed)
					removeTagBody._tags.push(_id: idTagUnclear)
				else if item.data.unclear
					addTagBody._tags.push(_id: idTagUnclear)
					removeTagBody._tags.push(_id: idTagRed)
				else
					removeTagBody._tags.push(_id: idTagRed)
					removeTagBody._tags.push(_id: idTagUnclear)
					addTagBody = null

				limit = 1000
				search = (offset = 0) =>
					xhrAddTag = new CUI.XHR
						method: "POST"
						url: easydbUrl + "/search"
						headers:
							'x-easydb-token' : easydbToken
						body:
							offset: offset,
							limit: limit,
							search: [
								type: "in",
								fields: fields,
								in: [item.data.idTaxon],
								bool: "must"
							],
							format: "long",
							objecttypes: objecttypes
					xhrAddTag.start().done((response) =>
						if not response.objects or response.objects.length == 0
							deferred.resolve()
							return

						idObjectsByObjecttype = {}
						response.objects.forEach((object) =>
							objecttype = object._objecttype
							if not idObjectsByObjecttype[objecttype]
								idObjectsByObjecttype[objecttype] = []
							idObject = object[objecttype]._id
							idObjectsByObjecttype[objecttype].push(idObject)
						)

						updatePromises = []
						for objecttype, ids of idObjectsByObjecttype
							removeTagBody._objecttype = objecttype
							removeTagBody[objecttype] = _id: ids
							body = [removeTagBody]

							if addTagBody
								addTagBody._objecttype = objecttype
								addTagBody[objecttype] = _id: ids
								body.push(addTagBody)

							xhrUpdateTags = new CUI.XHR
								method: "POST"
								url: easydbUrl + "/db/#{objecttype}?base_fields_only=1&format=short"
								headers:
									'x-easydb-token' : easydbToken
								body: body
							updatePromises.push(xhrUpdateTags.start())

						CUI.whenAll(updatePromises).done( =>
							if response.count > response.offset + limit
								offset += limit
								return search(offset)
							else
								return deferred.resolve()
						).fail((e) =>
							deferred.reject("custom.data.type.iucn.update.error.update-tags",
								idTaxon: item.data.idTaxon
								fields: fields
								easydbToken: easydbToken
								error: e?.response?.data
							)
							return
						)
					).fail((e)=>
						deferred.reject("custom.data.type.iucn.update.error.search-objects",
							idTaxon: item.data.idTaxon
							fields: fields
							easydbToken: easydbToken
							error: e?.response?.data
						)
						return
					)
				search()
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