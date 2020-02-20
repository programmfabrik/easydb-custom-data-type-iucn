class ez5.CustomBaseConfigIUCN extends BaseConfigPlugin

	getFieldDefFromParm: (baseConfig, fieldName, def) ->
		switch def.plugin_type
			when 'iucn_tag'
				options = [
					text: $$("server.config.parameter.system.iucn_settings.tag.placeholder.#{fieldName}")
					value: null
				]

				for tagGroup in ez5.tagForm.tagGroups
					options.push(label: tagGroup.getDisplayName())
					for tag in tagGroup.getTags()
						options.push
							text: tag.getDisplayName()
							value: tag.getId()
				field =
					type: CUI.Select
					name: fieldName
					options: options
			when 'iucn_field_name'
				options = @__searchInAllObjecttypes((field) ->
					return field instanceof CustomDataTypeIUCN and field.getFatherField() not instanceof ReverseLinkedTable # For now fields within a reverse linked table are skipped.
				)

				field =
					type: CUI.Select
					name: fieldName
					options: options
		return field

	# Search in all objecttypes using a 'filter' function.
	# Applies the filter function to each field and adds it to an array of options.
	__searchInAllObjecttypes: (filter) ->
		optionsByObjecttype = {}

		getFields = (idTable, path = "") ->
			mask = Mask.getMaskByMaskName("_all_fields", idTable)

			if path
				tableName = path.split(".")[0]
			else
				tableName = mask.table.name()

			tableNameLocalized = mask.table.nameLocalized()
			if not optionsByObjecttype[tableName]
				optionsByObjecttype[tableName] = [label: tableNameLocalized]

			mask.invokeOnFields("all", true, ((field) =>
				if field instanceof LinkedObject
					idLinkedTable = field.linkMask().table.id()
					if idLinkedTable == idTable # This is a field with a linked object to the same objecttype.
						return

					if field.insideNested() # Skip linked objects inside nested.
						return

					if field.table.id() == field.linkMask().table.id()
						return

					getFields(field.linkMask().table.id(), field.fullName() + ez5.IUCNUtil.LINK_FIELD_SEPARATOR)
					return

				if field instanceof ReverseLinkedTable
					return

				if not filter(field)
					return

				value = path + field.fullName()
				# Do not add duplicated fields (when 'edit' in linked object is enabled.)
				if optionsByObjecttype[tableName].some((option) -> option.value == value)
					return

				optionsByObjecttype[tableName].push
					text: field.nameLocalized()
					value: value
				return
			))

		for _, objecttype of ez5.schema.CURRENT._objecttype_by_name
			if objecttype.name.indexOf('@') > -1 # Skip connector objecttypes.
				continue
			getFields(objecttype.table_id)

		options = [
			text: $$("server.config.parameter.system.iucn_settings.iucn_fields.placeholder")
			value: null
		]
		for _, _options of optionsByObjecttype
			if _options.length == 1
				continue
			options = options.concat(_options)
		return options



ez5.session_ready =>
	BaseConfig.registerPlugin(new ez5.CustomBaseConfigIUCN())