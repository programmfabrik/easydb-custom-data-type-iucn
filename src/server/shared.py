import json
import requests


def parse_plugin_config(api_settings: dict) -> tuple[str, str]:

    api_url = None
    try:
        api_url = api_settings['api_url']
        if not isinstance(api_url, str):
            raise Exception('expected string')
        api_url = api_url.strip()
        if api_url == '':
            raise Exception('expected non-empty string')
    except Exception as e:
        raise Exception(f'could not load api_url from iucn_api_settings: {e}')

    api_token = None
    try:
        api_token = api_settings['api_token']
        if not isinstance(api_token, str):
            raise Exception('expected string')
        api_token = api_token.strip()
        if api_token == '':
            raise Exception('expected non-empty string')
    except Exception as e:
        raise Exception(f'could not load api_token from iucn_api_settings: {e}')

    return api_url, api_token


def perform_get_request(api_url: str, api_path: str, api_token: str) -> dict:
    resp = requests.get(
        url=f'{api_url}/{api_path}',
        headers={
            'Authorization': api_token,
        },
    )

    if resp.status_code == 200:
        return json.loads(resp.text)

    # when searching does not find a result, the api v4 answers with 404
    if resp.status_code == 404:
        return {}

    raise Exception(f'HTTP status code: {resp.status_code}, text: {resp.text}')
