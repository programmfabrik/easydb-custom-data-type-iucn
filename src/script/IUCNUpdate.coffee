class IUCNUpdate

	# Returns the base easydb URL.
	__getEasydbUrl: (easydb_api_url) ->
		if not easydb_api_url.endsWith("/api/v1")
			easydb_api_url += "/api/v1"
		return easydb_api_url

	__startUpdate: (data) ->
		@__login(data).done((easydbToken, easydbUrl) =>
			if not easydbToken
				ez5.respondError("custom.data.type.iucn.start-update.error.easydb-token-empty")
				return

			config = @__getConfig(data)
			if not config
				ez5.respondError("custom.data.type.iucn.start-update.error.server-config-empty")
				return

			state =
				easydbToken: easydbToken
				easydbUrl: easydbUrl
				config: {}

			for settingsKey in ["iucn_settings", "iucn_easydb_settings", "iucn_api_settings"]
				if not config[settingsKey]
					ez5.respondError("custom.data.type.iucn.start-update.error.#{settingsKey}-not-available-in-server-config")
					return
				state.config[settingsKey] = config[settingsKey] # Save necessary config in the state.

			ez5.respondSuccess(state: state)
		).fail((messageKey, opts) =>
			ez5.respondError(messageKey, opts)
		)
		return

	__getConfig: (data) ->
		return data.server_config?.base?.system

	__login: (data) ->
		config = @__getConfig(data)
		if not config
			return CUI.rejectedPromise("custom.data.type.iucn.start-update.error.server-config-empty")

		login = config.iucn_easydb_settings?.easydb_login
		password = config.iucn_easydb_settings?.easydb_password

		if not login or not password
			return CUI.rejectedPromise("custom.data.type.iucn.start-update.error.login-password-not-provided",
				login: login
				password: password
			)

		easydbApiUrl = data.server_config.system?.server?.internal_url
		if not easydbApiUrl
			return CUI.rejectedPromise("custom.data.type.iucn.start-update.error.easydb-api-url-not-configured")

		deferred = new CUI.Deferred()

		easydbUrl = @__getEasydbUrl(easydbApiUrl)
		# Get session, to get a valid token.
		getSessionUrl = "#{easydbUrl}/session"
		xhr = new CUI.XHR
			method: "GET"
			url: getSessionUrl
		xhr.start().done((response) =>
			# Authentication with login and password.
			authenticateUrl = "#{easydbUrl}/session/authenticate?login=#{login}&password=#{password}"
			xhr = new CUI.XHR
				method: "POST"
				url: authenticateUrl
				headers:
					'x-easydb-token' : response.token
			xhr.start().done((response) ->
				deferred.resolve(response?.token, easydbUrl)
			).fail((e) ->
				deferred.reject("custom.data.type.iucn.start-update.error.authenticate-server-error",
					e: e?.response?.data
					url: authenticateUrl
				)
			)
		).fail((e) ->
			deferred.reject("custom.data.type.iucn.start-update.error.get-session-server-error",
				e: e?.response?.data
				url: getSessionUrl
			)
		)
		return deferred.promise()

	__update: (data) ->
		apiSettings = data.state.config?.iucn_api_settings
		if not apiSettings
			ez5.respondError("custom.data.type.iucn.update.error.iucn_api_settings.not-available-in-state", state: data.state)
			return
		easydbApiUrl = data.state.easydbUrl
		if not easydbApiUrl
			ez5.respondError("custom.data.type.iucn.update.error.easydb-api-url-not-configured")
			return

		if not data.state.easydbToken
			return CUI.rejectedPromise("custom.data.type.iucn.update.error.not-easydb-token-in-state")

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

		# The response of the API returns 200 - 'message': "Token not valid!" when the token is not valid.
		# For now we will be using this to check it.
		chunkByName = CUI.chunkWork.call(@,
			items: Object.keys(objectsByNameMap)
			chunk_size: 1
			call: (items) =>
				scientificName = items[0]
				deferred = new CUI.Deferred()
				ez5.IUCNUtil.searchBySpecies(scientificName, apiSettings).done((response) =>
					if not response
						deferred.reject("custom.data.type.iucn.update.error.iucn-api-empty-response",
							iucn_api_settings: apiSettings
						)
						return
					if response.message == "Token not valid!"
						deferred.reject("custom.data.type.iucn.update.error.iucn-api-token-not-valid",
							iucn_api_settings: apiSettings
							response: response
						)
						return
					objectsFound = response.result
					if CUI.util.isEmpty(objectsFound)
						return deferred.resolve()
					foundData = ez5.IUCNUtil.setObjectData({}, objectsFound)
					for object in objectsByNameMap[scientificName]
						object.data = ez5.IUCNUtil.getSaveData(foundData)
						# Object is updated now. Next time that the script is executed with this object
						# the tags of the top level object will be updated.
						object.data.__updateTags = true
						objectsToUpdate.push(object)
					return deferred.resolve()
				).fail((responseError) =>
					return deferred.reject("custom.data.type.iucn.update.error.iucn-api-call", data: responseError.data, responseError.status);
				)
				return deferred.promise()
		)

		chunkById = CUI.chunkWork.call(@,
			items: Object.keys(objectsByIdMap)
			chunk_size: 1
			call: (items) =>
				id = items[0]
				deferred = new CUI.Deferred()
				ez5.IUCNUtil.searchBySpeciesId(id, apiSettings).done((response) =>
					if not response
						deferred.reject("custom.data.type.iucn.update.error.iucn-api-empty-response",
							iucn_api_settings: apiSettings
						)
						return
					if response.message == "Token not valid!"
						deferred.reject("custom.data.type.iucn.update.error.iucn-api-token-not-valid",
							iucn_api_settings: apiSettings
							response: response
						)
						return
					objectsFound = response.result
					if CUI.util.isEmpty(objectsFound)
						return deferred.resolve()
					foundData = ez5.IUCNUtil.setObjectData({}, objectsFound)
					for object in objectsByIdMap[id]
						if ez5.IUCNUtil.isEqual(object.data, foundData)
							# If the data did not change since the last time it was checked, and the __updateTags is true.
							# __updateTags will be undefined when the object is updated but it was never updated here before.
							if CUI.util.isUndef(object.data.__updateTags) or object.data.__updateTags
								object.data.__updateTags = false
								objectsToUpdateTags.push(object)
								objectsToUpdate.push(object)
						else
							object.data = ez5.IUCNUtil.getSaveData(foundData)
							object.data.__updateTags = true
							objectsToUpdate.push(object)
					return deferred.resolve()
				).fail((responseError) =>
					return deferred.reject("custom.data.type.iucn.update.error.iucn-api-call", data: responseError.data, responseError.status);
				)
				return deferred.promise()
		)

		return CUI.when([chunkByName, chunkById]).done( =>
			@__updateTags(objectsToUpdateTags, data).done(=>
				response = payload: objectsToUpdate
				if data.batch_info and data.batch_info.offset + data.objects.length >= data.batch_info.total
					easydbUrl = @__getEasydbUrl(easydbApiUrl)
					xhr = new CUI.XHR
						method: "POST"
						url: "#{easydbUrl}/session/deauthenticate"
					xhr.start().always(=>
						ez5.respondSuccess(response)
					)
				else
					ez5.respondSuccess(response)
			).fail((messageKey, opts = {}) =>
				ez5.respondError(messageKey, opts)
			)
		).fail((messageKey, opts = {}, statusCode) =>
			ez5.respondError(messageKey, opts, statusCode)
		)

	__updateTags: (objects, data) ->
		if objects.length == 0
			return CUI.resolvedPromise()

		easydbUrl = @__getEasydbUrl(data.state.easydbUrl)
		iucnSettings = data.state.config.iucn_settings

		idTagRed = iucnSettings.tag_red
		idTagUnclear = iucnSettings.tag_unclear
		iucnFields = iucnSettings.iucn_fields

		if not iucnFields or not idTagRed or not idTagUnclear
			return CUI.rejectedPromise("custom.data.type.iucn.update.error.not-available-settings")

		easydbToken = data.state.easydbToken

		linkSeparator = ez5.IUCNUtil.LINK_FIELD_SEPARATOR

		linkedFields = []
		fields = []
		iucnFields.forEach((field) ->
			if field.iucn_field_name.indexOf(linkSeparator) != -1
				fieldName = field.iucn_field_name
				index = fieldName.indexOf(linkSeparator)
				linkedFields.push
					linked_field: fieldName.substring(0, index)
					field: fieldName.substring(index + linkSeparator.length) + ".idTaxon"
			else
				fields.push(field.iucn_field_name + ".idTaxon")
		)

		searchLimit = 1000
		return CUI.chunkWork.call(@,
			items: objects
			chunk_size: 1
			call: (items) =>
				item = items[0]

				# Search all objects which contain the idTaxon of the item and update the tags with the values of the item.
				updateTags = (_fields, linked = false) ->
					if _fields.length == 0
						return CUI.resolvedPromise()

					if linked
						_linkedFields = _fields.map((_field) -> _field.linked_field + "._global_object_id")
						_fields = _fields.map((_field) -> _field.field)

					# Prepare tags body
					deferred = new CUI.Deferred()
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
					#

					# Update tags of objects.
					# When the item is in the red list, it adds the red list tag and removes unclear tag.
					# When the item is unclear, it adds the unclear tag and removes red list tag.
					# Otherwise, it removes all tags.
					update = (objects) ->
						idObjectsByObjecttype = {}
						objects.forEach((object) =>
							objecttype = object._objecttype
							if not idObjectsByObjecttype[objecttype]
								idObjectsByObjecttype[objecttype] = []
							idObject = object[objecttype]._id
							idObjectsByObjecttype[objecttype].push(idObject)
						)

						updatePromises = []
						for objecttype, ids of idObjectsByObjecttype
							_removeTagBody = CUI.util.copyObject(removeTagBody, true)
							_addTagBody = CUI.util.copyObject(addTagBody, true)

							_removeTagBody._objecttype = objecttype
							_removeTagBody[objecttype] = _id: ids
							body = [_removeTagBody]

							if _addTagBody
								_addTagBody._objecttype = objecttype
								_addTagBody[objecttype] = _id: ids
								body.push(_addTagBody)

							updateTagsOpts =
								method: "POST"
								url: easydbUrl + "/db/#{objecttype}?base_fields_only=1&format=short"
								headers:
									'x-easydb-token': easydbToken
								body: body
							xhrUpdateTags = new CUI.XHR(updateTagsOpts)
							updateTagsPromise = xhrUpdateTags.start().fail((e) =>
								deferred.reject("custom.data.type.iucn.update.error.update-tags",
									request: updateTagsOpts
									error: e?.response?.data
								)
							)
							updatePromises.push(updateTagsPromise)
						return CUI.when(updatePromises)

					# Search for objects that contain an object which contain an idTaxon.
					searchLinked = (objects) =>
						searchLinkedDeferred = new CUI.Deferred()
						_search = (offset = 0) =>
							# When it is a linked search, the objects of the previous search are not updated but used to search
							# linked objects to those objects.
							objecttypes = _linkedFields.map((fullname) -> fullname.split(".")[0])
							idObjects = objects.map((object) -> object._global_object_id)
							searchOpts =
								method: "POST"
								url: easydbUrl + "/search"
								headers:
									'x-easydb-token' : easydbToken
								body:
									offset: offset,
									limit: searchLimit,
									search: [
										type: "in",
										fields: _linkedFields,
										in: idObjects,
										bool: "must"
									],
									format: "short",
									objecttypes: objecttypes
							xhrLinkSearch = new CUI.XHR(searchOpts)
							xhrLinkSearch.start().done((response) =>
								if not response.objects or response.objects.length == 0
									searchLinkedDeferred.resolve()
									return
								update(response.objects).done(=>
									if response.count > response.offset + searchLimit
										offset += searchLimit
										return _search(offset)
									else
										return searchLinkedDeferred.resolve()
								)
								return
							).fail((e)=>
								deferred.reject("custom.data.type.iucn.update.error.search-linked-objects",
									request: searchOpts
									error: e?.response?.data
								)
								return
							)
						_search()
						return searchLinkedDeferred.promise()

					# Search for objects containing idTaxon.
					search = (offset = 0) =>
						objecttypes = _fields.map((fullname) -> fullname.split(".")[0])
						searchOpts =
							method: "POST"
							url: easydbUrl + "/search"
							headers:
								'x-easydb-token' : easydbToken
							body:
								offset: offset,
								limit: searchLimit,
								search: [
									type: "in",
									fields: _fields,
									in: [item.data.idTaxon],
									bool: "must"
								],
								format: "short",
								objecttypes: objecttypes
						xhrSearch = new CUI.XHR(searchOpts)
						xhrSearch.start().done((response) =>
							if not response.objects or response.objects.length == 0
								deferred.resolve()
								return
							objects = response.objects

							if linked
								promise = searchLinked(objects)
							else
								promise = update(objects)

							promise.done(=>
								if response.count > response.offset + searchLimit
									offset += searchLimit
									return search(offset)
								else
									return deferred.resolve()
							)
							return
						).fail((e)=>
							deferred.reject("custom.data.type.iucn.update.error.search-objects",
								request: searchOpts
								error: e?.response?.data
							)
							return
						)
					search()
					return deferred.promise()

				# Update tags is called twice, one for normal fields and one for linked objects.
				return CUI.when(updateTags(fields), updateTags(linkedFields, true))
		)

	main: (data) ->
		if not data
			ez5.respondError("custom.data.type.iucn.update.error.payload-missing")
			return

		for key in ["action", "plugin_config"]
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