class CustomDataTypeIUCN extends CustomDataType

	getCustomDataTypeName: ->
		return ez5.IUCNUtil.getFieldType()

	getCustomDataTypeNameLocalized: ->
		return	$$("custom.data.type.iucn.name")

	getCustomDataOptionsInDatamodelInfo: ->
		return []

	renderEditorInput: (data) ->
		# TODO: Show error label when API url is not set. ez5.IUCNUtil.getApiSettings() api_url api_token
		data = @__initData(data)
		div = CUI.dom.div()

		toggleOutput = =>
			CUI.Events.trigger
				node: div
				type: "editor-changed"

			if data.idTaxon
				output = @__getOutput(data, true, =>
					ez5.IUCNUtil.setObjectData(data, {}) # Empty data.
					toggleOutput()
				)
				CUI.dom.replace(div, output)
			else
				CUI.dom.replace(div, searchField)

		searchField = @__getSearchField(data, toggleOutput)
		toggleOutput()

		return div

	__getSearchField: (data, onSearch) ->
		searchButton = new CUI.Button
			icon: "search"
			class: "ez5-custom-data-type-iucn-search-button"
			tooltip:
				text: $$("custom.data.type.iucn.editor.search-button.tooltip")
			onClick: =>
				searchButton.startSpinner()
				ez5.IUCNUtil.searchBySpecies(data.searchName).done((response) ->
					# TODO: What to do if it returns more than 1 result. It takes the first one for now.
					_data = response.result[0]
					if _data
						delete data.__notFound
						ez5.IUCNUtil.setObjectData(data, _data)
					else
						data.__notFound
					onSearch()
				).always(-> searchButton.stopSpinner())

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


		layout = new CUI.HorizontalLayout
			center:
				content: searchInput
			right:
				content: searchButton
		return layout

	__getOutput: (data, isEditor = false, onDelete) ->
		if data.redList
			redListText = $$("custom.data.type.iucn.output.red-list.text")
		else
			redListText = $$("custom.data.type.iucn.output.red-list.text")

		list = new CUI.VerticalList(content: [
			new CUI.Label(text: data.mainCommonName, appearance: "title", multiline: true)
			new CUI.Label(text: "#{data.idTaxon} - #{data.scientificName}", appearance: "secondary")
			new CUI.Label(text: redListText, appearance: "secondary")
		])

		if isEditor
			menuButton = new LocaButton
				loca_key: "custom.data.type.iucn.output.menu.button"
				icon: "ellipsis_v"
				icon_right: false
				appearance: "flat"
				menu:
					items: [
						new LocaButton
							loca_key: "custom.data.type.iucn.output.menu.delete-button"
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

		layout = new CUI.HorizontalLayout(
			class: "ez5-field-object ez5-custom-data-type-iucn-card"
			left:
				content: @__getLogoImage()
			center:
				content: list
			right:
				content: rightContent
		)
		return layout

	renderDetailOutput: (data, _, opts) ->
		data = @__initData(data)
		if not data.idTaxon
			return CUI.dom.div() # TODO: empty Label with 'not set' text.
		return @__getOutput(data)

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		return save_data[@name()] = ez5.IUCNUtil.getSaveData(data)

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

CustomDataType.register(CustomDataTypeIUCN)