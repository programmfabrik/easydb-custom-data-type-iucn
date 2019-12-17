class CustomDataTypeIUCN extends CustomDataType

	getCustomDataTypeName: ->
		return "custom:base.custom-data-type-iucn.iucn"

	getCustomDataTypeNameLocalized: ->
		return	$$("custom.data.type.iucn.name")

	getCustomDataOptionsInDatamodelInfo: ->
		return []

	renderEditorInput: (data) ->

	renderDetailOutput: (data, _, opts) ->

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		return save_data[@name()] = IUCNUtil.getSaveData(data)

CustomDataType.register(CustomDataTypeIUCN)