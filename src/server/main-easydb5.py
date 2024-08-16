# coding=utf8

import json
import shared
from context import get_json_value

PLUGIN = 'custom_data_type_iucn'
ENDPOINT = 'proxy_api_v4'


def easydb_server_start(easydb_context):
    logger = easydb_context.get_logger(f'base.{PLUGIN}')
    easydb_context.register_callback(
        'api',
        {
            'name': ENDPOINT,
            'callback': ENDPOINT,
        },
    )
    logger.info(f'registered api endpoint: api/plugin/base/{PLUGIN}/{ENDPOINT}')


def json_response(js, status_code=200):
    return {
        'status_code': status_code,
        'body': json.dumps(js, indent=4),
        'headers': {
            'Content-Type': 'application/json; charset=utf-8',
        },
    }


def error_json_response(js):
    return json_response(
        {
            'error': js,
        },
        status_code=500,
    )


def proxy_api_v4(easydb_context, parameters):
    logger = easydb_context.get_logger(f'base.{PLUGIN}')

    # logger.debug(f'parameters: {json.dumps(parameters,indent=4)}')

    # load query
    iucn_api_path = None
    try:
        query = parameters['query_string_parameters']
        iucn_query = query['iucn_query']
        if not isinstance(iucn_query, list):
            raise Exception('expected non empty array')
        if len(iucn_query) < 1:
            raise Exception('expected non empty array')
        iucn_api_path = iucn_query[0]
    except Exception as e:
        return error_json_response(
            f'could not load query from info.json.request.query.iucn_query: {e}'
        )

    config = easydb_context.get_config()
    # logger.debug(f'config: {json.dumps(config,indent=4)}')

    iucn_api_url = get_json_value(config, 'base.system.iucn_api_settings.api_url')
    iucn_api_token = get_json_value(config, 'base.system.iucn_api_settings.api_token')
    logger.debug(f'iucn api path: {iucn_api_url}/{iucn_api_path}')

    try:
        response = shared.perform_get_request(
            api_url=iucn_api_url,
            api_token=iucn_api_token,
            api_path=iucn_api_path,
        )
        if not isinstance(response, dict):
            raise Exception('expected response as json dict')
        return json_response(response)

    except Exception as e:
        return error_json_response(str(e))
