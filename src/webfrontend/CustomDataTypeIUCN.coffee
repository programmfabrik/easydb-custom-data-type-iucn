class CustomDataTypeIUCN extends CustomDataType

	getCustomDataTypeName: ->
		return ez5.IUCNUtil.getFieldType()

	getCustomDataTypeNameLocalized: ->
		return	$$("custom.data.type.iucn.name")

	getCustomDataOptionsInDatamodelInfo: ->
		return []

	renderSearchInput: (data, opts={}) ->
		return new SearchToken(
			column: @
			data: data
			fields: opts.fields
		).getInput().DOM

	getFieldNamesForSearch: ->
		@__getFieldNames()

	getFieldNamesForSuggest: ->
		@__getFieldNames()

	getSearchFilter: (data, key=@name()) ->
		if data[key+":unset"]
			filter =
				type: "in"
				fields: [ @fullName()+".scientificName" ]
				in: [ null ]
			filter._unnest = true
			filter._unset_filter = true
			return filter

		filter = super(data, key)
		if filter
			return filter

		if CUI.util.isEmpty(data[key])
			return

		val = data[key]
		[str, phrase] = Search.getPhrase(val)

		switch data[key+":type"]
			when "token", "fulltext", undefined
				filter =
					type: "match"
					mode: data[key+":mode"]
					fields: @getFieldNamesForSearch()
					string: str
					phrase: phrase
			when "field"
				filter =
					type: "in"
					fields: @getFieldNamesForSearch()
					in: [ str ]
		filter

	__getFieldNames: ->
		fieldNames = [
			@fullName()+".idTaxon"
			@fullName()+".scientificName"
			@fullName()+".mainCommonName"
		]
		return fieldNames

	getQueryFieldBadge: (data) =>
		if data["#{@name()}:unset"]
			value = $$("text.column.badge.without")
		else
			value = data[@name()]
		name: @nameLocalized()
		value: value

	renderEditorInput: (data) ->
		data = @__initData(data)
		div = CUI.dom.div()

		toggleOutput = =>
			CUI.Events.trigger
				node: div
				type: "editor-changed"

			if data.idTaxon or data.scientificName
				output = @__getOutput(data, true, =>
					ez5.IUCNUtil.setObjectData(data) # Empty data.
					toggleOutput()
				)
				CUI.dom.replace(div, output)
			else
				CUI.dom.replace(div, searchField)

		searchField = @__getSearchField(data, toggleOutput)
		toggleOutput()

		return div

	__getSearchField: (data, onSearch) ->
		doSearch = =>
			searchButton.startSpinner()
			ez5.IUCNUtil.searchBySpecies(data.searchName).done((response) ->
				if not response or response.message == "Token not valid!"
					CUI.alert(text: $$("custom.data.type.iucn.editor.search.token-invalid"), markdown: true)
					return
				_data = response.result
				if CUI.util.isEmpty(_data)
					ez5.IUCNUtil.setObjectData(data, scientific_name: data.searchName)
				else
					ez5.IUCNUtil.setObjectData(data, _data)
				onSearch()
			).always(-> searchButton.stopSpinner())

		searchButton = new CUI.Button
			icon: "search"
			class: "ez5-custom-data-type-iucn-search-button"
			tooltip:
				text: $$("custom.data.type.iucn.editor.search-button.tooltip")
			onClick: doSearch

		toggleButton = ->
			if CUI.util.isEmpty(data.searchName)
				searchButton.disable()
			else
				searchButton.enable()
			return

		searchInput = new CUI.Input
			data: data
			class: "ez5-custom-data-type-iucn-search-input"
			name: "searchName"
			placeholder: $$("custom.data.type.iucn.editor.search-input.placeholder")
			onDataInit: toggleButton
			onDataChanged: toggleButton
		searchInput.start()

		CUI.Events.listen
			node: searchInput
			type: "keyup"
			call: (ev) =>
				if ev.keyCode() != 13
					return
				doSearch()
				return

		layout = new CUI.HorizontalLayout
			center:
				content: searchInput
			right:
				content: searchButton
		return layout

	__getOutput: (data, isEditor = false, onDelete) ->
		if data.redList
			statusText = $$("custom.data.type.iucn.output.status.red-list.text")
		else
			statusText = $$("custom.data.type.iucn.output.no-status.text")

		if isEditor
			menuButton = new LocaButton
				loca_key: "custom.data.type.iucn.editor.menu.button"
				icon: "ellipsis_v"
				icon_right: false
				appearance: "flat"
				menu:
					items: [
						new LocaButton
							loca_key: "custom.data.type.iucn.editor.menu.delete-button"
							onClick: =>
								onDelete?()
					]

		rightContent = new CUI.HorizontalLayout(right: content: "")
		if data.redList
			idRedListTag = ez5.IUCNUtil.getSettings()?.tag_red
			tag = ez5.tagForm.findTagByAnyId(idRedListTag)
			if tag
				rightContent.append(tag.getLabel(), "center")

		if isEditor
			rightContent.append(menuButton, "right")

		if data.idTaxon
			content = new CUI.VerticalList(content: [
				new CUI.Label(text: data.mainCommonName, appearance: "title", multiline: true)
				new CUI.Label(text: "#{data.idTaxon} - #{data.scientificName}", appearance: "secondary")
				new CUI.Label(text: statusText, appearance: "secondary")
			])
		else
			content = new CUI.Label(text: data.scientificName)

		layout = new CUI.HorizontalLayout(
			class: "ez5-field-object ez5-custom-data-type-iucn-card"
			left:
				content: @__getLogoImage()
			center:
				content: content
			right:
				content: rightContent
		)
		return layout

	renderDetailOutput: (data, _, opts) ->
		data = @__initData(data)
		return @__getOutput(data)

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		return save_data[@name()] = ez5.IUCNUtil.getSaveData(data)

	isEmpty: (data, _, opts = {}) ->
		data = data[@name()]

		if opts.mode == "expert"
			return CUI.util.isEmpty(data?.trim())

		return CUI.util.isEmpty(data?.idTaxon) and CUI.util.isEmpty(data?.scientificName)

	__initData: (data) ->
		if not data[@name()]
			initData = {}
			data[@name()] = initData
		else
			initData = data[@name()]
		initData

	__getLogoImage: ->
		if @__previewImage
			return @__previewImage
		plugin = ez5.pluginManager.getPlugin("custom-data-type-iucn")
		@__previewImage = new Image()
		@__previewImage.src = plugin.getBaseURL() + plugin.getWebfrontend().logo
		return @__previewImage

	renderFieldAsGroup: ->
		return false

	supportsStandard: ->
		return true

CustomDataType.register(CustomDataTypeIUCN)