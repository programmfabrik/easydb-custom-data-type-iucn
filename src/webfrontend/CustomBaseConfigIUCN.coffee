class CustomBaseConfigIUCN extends BaseConfigPlugin

	getFieldDefFromParm: (baseConfig, fieldName, def) ->
		switch def.plugin_type
			when 'iucn_tag'
				options = [
					text: $$("server.config.parameter.system.iucn_settings.tag.placeholder.#{fieldName}")
					value: null
				]

				for tagGroup in ez5.tagForm.tagGroups
					for tag in tagGroup.getTags()
						options.push
							text: tagGroup.getDisplayName() + ": " + tag.getDisplayName() # TODO: Separator in CUI.Select with label
							value: tag.getId()
				field =
					type: CUI.Select
					name: fieldName
					options: options
			when 'iucn_objecttype', 'iucn_objecttype_link'
				field =
					type: CUI.Select
					name: fieldName
					onDataChanged: (data, field) ->
						if def.plugin_type == 'iucn_objecttype'
							field.getForm().getFieldsByName("objecttype_with_link")[0].reload()
					options: (field) =>
						if def.plugin_type == 'iucn_objecttype'
							@__getOptionsForObjecttypeDirect()
						else
							data = field.getForm().getData()
							@__getOptionsForObjecttypeLink(data.objecttype_direct)

		return field

	__getOptionsForObjecttypeLink: (idObjecttype) ->
		options = []
		if not idObjecttype
			return options

		@__searchInAllObjecttypes((field) ->
			if not field.FieldSchema?.other_table_id
				return

			# Only LinkedObject and ReverseLinkedTable fields.
			if field not instanceof LinkedObject and field not instanceof ReverseLinkedTable
				return

			# Check whether the linked-object/reverse-linked links to the given idObjecttype.
			return field.FieldSchema.other_table_id == idObjecttype
		, options)
		return options

	__getOptionsForObjecttypeDirect: ->
		if @__objecttypes
			return @__objecttypes

		@__objecttypes = []
		@__searchInAllObjecttypes((field) ->
			return field instanceof CustomDataTypeIUCN and
				field.getFatherField() not instanceof ReverseLinkedTable # For now fields within a reverse linked table are skipped.
		, @__objecttypes)
		return @__objecttypes

	# Search in all objecttypes using a 'filter' function.
	# If filter returns true, it adds the objecttype to 'objecttypeOptions'.
	__searchInAllObjecttypes: (filter, objecttypeOptions) ->
		for _, objecttype of ez5.schema.CURRENT._objecttype_by_name
			if objecttype.name.indexOf('@') > -1 # Skip connector objecttypes.
				continue

			idTable = objecttype.table_id
			mask = Mask.getMaskByMaskName("_all_fields", idTable)
			mask.invokeOnFields("all", true, ((field) =>
				if not filter(field)
					return

				objecttypeOptions.push
					text: objecttype._name_localized
					value: idTable
				return false
			))



ez5.session_ready =>
	BaseConfig.registerPlugin(new CustomBaseConfigIUCN())