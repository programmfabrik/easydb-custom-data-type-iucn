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

		easydbApiUrl = data.server_config.system?.server?.external_url
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

		deferred = new CUI.Deferred()

		objectsToUpdate = []
		objectsToUpdateTags = []
		objectsNotFound = []

		speciesByName = {}
		speciesById = {}

		# This is expected to be the endpoint of the plugin.
		ez5.session = {
			token: data.state.easydbToken
		}
		endpoint = data.state.easydbUrl + "/plugin/extension/custom-data-type-iucn/proxy_api_v4"
		searchIdx = 0

		process_object = (object) =>
			dfr = new CUI.Deferred()
			# Start measuring time
			startTime = process.hrtime()
			if not CUI.util.isEmpty(object.data.idTaxon)
				# console.log "Search by taxon id: #{JSON.stringify(object.data.idTaxon)}"
				searchPromise = ez5.IUCNUtil.searchBySisTaxonId(endpoint, object.data.idTaxon)
			else if not CUI.util.isEmpty(object.data.scientificName)
				# console.log "Searching by taxon name: #{object.data.scientificName}"
				parts = object.data.scientificName.split(/\s+/).filter (part) -> part.trim() != ""
				genus = ""
				species = ""
				if parts.length > 0
					genus = parts[0]
				if parts.length > 1
					species = parts[1]
				searchPromise = ez5.IUCNUtil.searchByTaxonname(endpoint, genus, species)
			else
				# console.log "No taxon id or scientific name found"
				dfr.reject()
				return dfr.promise()


			# The search of an object is made in two steps:
			# 1) Search by taxon id or scientific name
			# 2) Get the assessment data
			searchPromise.done( (response) ->
				if CUI.util.isEmpty response
					# If the response is empty, it means that the object was not found in the IUCN API.
					# We need to clear the tags of objects linking to those objects. We will do that later.
					objectsNotFound.push(object)
					dfr.resolve()
					return
				_assessment_id = ez5.IUCNUtil.getLatestAssessmentIdFromSearchResult(response)
				ez5.IUCNUtil.getAssessmentData(endpoint, _assessment_id).done((response) ->
					if CUI.util.isEmpty response
						objectsNotFound.push(object)
						dfr.resolve()
						return
					foundData = ez5.IUCNUtil.setObjectData({}, response)
					object.data = ez5.IUCNUtil.getSaveData(foundData)
					object.data.__updateTags = true
					objectsToUpdateTags.push(object)
					objectsToUpdate.push(object)

					# Check elapsed time
					endTime = process.hrtime(startTime)
					# endTime[0] is seconds, endTime[1] is nanoseconds
					elapsedMs = (endTime[0] * 1000) + (endTime[1] / 1000000)
					# If less than 1000ms have passed, we can decide to wait the remaining time
					# so that each request takes at least 1 second
					desiredDelay = 1000  # 1 second in ms
					if elapsedMs < desiredDelay
						remainingTime = desiredDelay - elapsedMs
						setTimeout(() ->
							dfr.resolve()
						, remainingTime)
					else
						dfr.resolve()
				).fail((e) ->
					dfr.reject()
				)
			).fail((e) ->
				# console.log "Search by taxon id failed: " + e
				dfr.reject()
			)
			return dfr.promise()


		# console.log "Start Processing Objects"
		# IMPORTANT: The v4 API has a limit of 120 requests per minute.
		# So we need to wait at least 1 second between requests. (we make 2 requests per object)
		CUI.chunkWork.call(@,
			items: data.objects
			chunk_size: 1
			call: (batch) =>
				return process_object(batch[0])
		).fail( =>
			ez5.respondError("custom.data.type.iucn.update.error.iucn-api-call")
		).done( =>
			# console.log("All objects processed")
			# console.log "Objects to update: #{objectsToUpdate.length}"
			# console.log "Objects to update tags: #{objectsToUpdateTags.length}"
			# console.log "Objects not found: #{objectsNotFound.length}"

			for objectNotFound in objectsNotFound
				objectNotFound.redList = false
				objectsToUpdate.push(objectNotFound)
				objectsToUpdateTags.push(objectNotFound)

			@__updateTags(objectsToUpdateTags, data).done( =>
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

		)
		return deferred.promise()


	__updateTags: (objects, data) ->
		if objects.length == 0
			return CUI.resolvedPromise()

		#console.log "Updating tags of objects", JSON.stringify(objects, null, 2), "with data", JSON.stringify(data, null, 2)

		easydbUrl = @__getEasydbUrl(data.state.easydbUrl)
		iucnSettings = data.state.config.iucn_settings

		idTagRed = iucnSettings.tag_red
		iucnFields = iucnSettings.iucn_fields

		if not iucnFields or not idTagRed
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
						#console.log "Adding red list tag to object with idTaxon: #{item.data.idTaxon}, scientificName: #{item.data.scientificName}, Item: #{JSON.stringify(item, null, 2)}"
						addTagBody._tags.push(_id: idTagRed)
						removeTagBody = null
					else
						#console.log "Removing red list tag from object with idTaxon: #{item.data.idTaxon}, scientificName: #{item.data.scientificName}, Item: #{JSON.stringify(item, null, 2)}"
						removeTagBody._tags.push(_id: idTagRed)
						addTagBody = null
					#

					# Update tags of objects.
					# When the item is in the red list, it adds the red list tag.
					# Otherwise, it removes all tags.
					update = (objects) ->
						# console.log("Updating tags of objects", JSON.stringify(objects, null, 2))
						idObjectsByObjecttype = {}
						objects.forEach((object) =>
							objecttype = object._objecttype
							if not idObjectsByObjecttype[objecttype]
								idObjectsByObjecttype[objecttype] = []
							idObject = object[objecttype]._id
							idObjectsByObjecttype[objecttype].push(idObject)
						)

						#console.log "Updating tags of objects: #{JSON.stringify(idObjectsByObjecttype, null, 2)}"

						updatePromises = []
						for objecttype, ids of idObjectsByObjecttype
							#console.log "Updating tags of objecttype: #{objecttype}, ids: #{JSON.stringify(ids, null, 2)}"
							_removeTagBody = CUI.util.copyObject(removeTagBody, true)
							_addTagBody = CUI.util.copyObject(addTagBody, true)

							#console.log "Remove tags body: #{JSON.stringify(_removeTagBody, null, 2)}"
							#console.log "Add tags body: #{JSON.stringify(_addTagBody, null, 2)}"

							body = []

							if _removeTagBody
								_removeTagBody._objecttype = objecttype
								_removeTagBody[objecttype] = _id: ids
								body.push(_removeTagBody)

							if _addTagBody
								_addTagBody._objecttype = objecttype
								_addTagBody[objecttype] = _id: ids
								body.push(_addTagBody)

							#console.log "Update tags body: #{JSON.stringify(body, null, 2)}"

							updateTagsOpts =
								method: "POST"
								url: easydbUrl + "/db/#{objecttype}?base_fields_only=1&format=short"
								headers:
									'x-easydb-token': easydbToken
								body: body

							#console.log "Update tags request: #{JSON.stringify(updateTagsOpts, null, 2)}"

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
							# console.log "Search for linked objects: #{JSON.stringify(searchOpts, null, 2)}"
							xhrLinkSearch.start().done((response) =>
								# console.log("Search for linked objects - Response: #{JSON.stringify(response, null, 2)}")
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
						#console.log "Searching objects with idTaxon: #{item.data.idTaxon}"
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
							# console.log("Search for objects with idTaxon: #{item.data.idTaxon} - Response: #{JSON.stringify(response, null, 2)}")
							if not response.objects or response.objects.length == 0
								#console.log "No objects found for search: #{JSON.stringify(searchOpts, null, 2)}"
								deferred.resolve()
								return
							objects = response.objects

							if linked
								# console.log("Search for linked objects")
								promise = searchLinked(objects)
							else
								# console.log "Update objects"
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
				#console.log("Update Tags for fields ", JSON.stringify(fields, null, 2))
				#console.log("Update Tags for linked fields ", JSON.stringify(linkedFields, null, 2))
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
