# coding=utf8

import json
import sys
import shared

PLUGIN = 'custom_data_type_iucn'
ENDPOINT = 'proxy_api_v4'


def error(line: str) -> None:
    sys.stderr.write(line)
    exit(1)


def main() -> None:
    if len(sys.argv) < 2:
        error('expect info.json as first parameter')

    # parse info.json parameter
    info_json = None
    try:
        info_json = json.loads(sys.argv[1])
    except Exception as e:
        error(f'could not parse info.json: {e}')

    # load query
    iucn_api_path = None
    try:
        request = info_json['request']
        query = request['query']
        iucn_query = query['iucn_query']
        if not isinstance(iucn_query, list):
            raise Exception('expected non empty array')
        if len(iucn_query) < 1:
            raise Exception('expected non empty array')
        iucn_api_path = iucn_query[0]
    except Exception as e:
        error(f'could not load query from info.json.request.query.iucn_query: {e}')

    # load config
    iucn_api_url = None
    iucn_api_token = None
    try:
        config = info_json['config']
        plugin = config['plugin']
        custom_data_type_iucn = plugin['custom-data-type-iucn']
        config = custom_data_type_iucn['config']
        iucn_api_settings = config['iucn_api_settings']
        iucn_api_url, iucn_api_token = shared.parse_plugin_config(iucn_api_settings)
    except Exception as e:
        error(f'could not parse iucn_api_settings: {e}')

    try:
        response = shared.perform_get_request(
            api_url=iucn_api_url,
            api_token=iucn_api_token,
            api_path=iucn_api_path,
        )
        if not isinstance(response, dict):
            raise Exception('expected response as json dict')
        sys.stdout.write(json.dumps(response))
    except Exception as e:
        raise e
        error(f'could not perform request to IUCN API {iucn_api_url}: {e}')


if __name__ == '__main__':
    main()
