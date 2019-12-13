class CustomBaseConfigIUCN extends BaseConfigPlugin

	getFieldDefFromParm: (baseConfig, fieldName, def) ->

ez5.session_ready =>
	BaseConfig.registerPlugin(new CustomBaseConfigIUCN())