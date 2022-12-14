# coding=utf8

from context import InvalidValueError
from context import TypeMismatchError

from fylr_lib_plugin_python3 import util
from objects import IucnObjectHandler


global PLUGIN_NAME
global LOGGER_NAME
PLUGIN_NAME = 'custom_data_type_iucn'
LOGGER_NAME = 'pf.plugin.base.' + PLUGIN_NAME

MAIN_OBJECTTYPES = [
    'entomologie',
    'fungarium',
    'herbarien',
    'xylothek',
]

MEDIAASSETPUBLIC = 'mediaassetpublic'
MEDIAASSETNONPUBLIC = 'mediaassetnonpublic'


@util.handle_exceptions
def easydb_server_start(easydb_context):
    global LOGGER_NAME
    logger = easydb_context.get_logger(LOGGER_NAME)
    logger.debug('debugging is activated')

    easydb_context.register_callback('db_post_update', {
        'callback': 'pre_update'
    })


@util.handle_exceptions
def pre_update(easydb_context, easydb_info):
    global LOGGER_NAME
    logger = easydb_context.get_logger(LOGGER_NAME)

    data = util.get_json_value(easydb_info, 'data')
    if not isinstance(data, list):
        logger.warn('object data is not a list -> skip')
        return data
    if len(data) < 1:
        logger.warn('object data list is empty -> skip')
        return data

    # skip non-relevant objecttypes
    main_objecttype = util.get_json_value(data[0], '_objecttype')
    if main_objecttype not in MAIN_OBJECTTYPES:
        logger.debug('objecttype {0} not in [{1}] -> skip'.format(
            main_objecttype, ', '.join(MAIN_OBJECTTYPES)))
        return data

    # logger.debug('data: {0}'.format(util.dumpjs(data)))

    session = easydb_context.get_session()
    user_id = util.get_json_value(session, 'user.user._id')
    if not isinstance(user_id, int):
        raise TypeMismatchError('session.user.user._id', 'int')
    logger.debug('user id: {0}'.format(user_id))

    iucnObjectsHandler = IucnObjectHandler(
        easydb_context, LOGGER_NAME, user_id)

    token = util.get_json_value(session, 'token')
    if not isinstance(token, str):
        raise TypeMismatchError('session.token', 'str')
    logger.debug('session token valid')

    # load info from the base config
    config = easydb_context.get_config()
    if not isinstance(config, dict):
        raise TypeMismatchError('config', 'dict')

    # easydb_login = util.get_json_value(
    #     config,
    #     'base.system.iucn_easydb_settings.easydb_login')
    # if not isinstance(easydb_login, str) or len(easydb_login) < 1:
    #     raise InvalidValueError(
    #         'base.system.iucn_easydb_settings.easydb_login',
    #         '\'{}\''.format(str(easydb_login)),
    #         'non-empty string')
    # easydb_password = util.get_json_value(
    #     config,
    #     'base.system.iucn_easydb_settings.easydb_password')
    # if not isinstance(easydb_password, str) or len(easydb_password) < 1:
    #     raise InvalidValueError(
    #         'base.system.iucn_easydb_settings.easydb_password',
    #         '\'{}\''.format(str(easydb_password)),
    #         'non-empty string')

    tag_red = util.get_json_value(
        config,
        'base.system.iucn_settings.tag_red')
    if not isinstance(tag_red, int):
        raise InvalidValueError(
            'base.system.iucn_settings.tag_red',
            '\'{}\''.format(str(tag_red)),
            'tag id (int)')
    logger.debug('tag IUCNREDLIST: id {0}'.format(tag_red))

    tag_unclear = util.get_json_value(
        config,
        'base.system.iucn_settings.tag_unclear')
    if not isinstance(tag_unclear, int):
        raise InvalidValueError(
            'base.system.iucn_settings.tag_unclear',
            '\'{}\''.format(str(tag_unclear)),
            'tag id (int)')
    logger.debug('tag IUCNUNCLEAR: id {0}'.format(tag_unclear))

    # iterate over the objects, check the tags
    # map objects: collect all objects that have one of the tags, and all objects that have none of the tags
    objects_with_iucn_tags = set()
    objects_without_iucn_tags = set()
    group_edit = False
    for obj in data:

        # only consider updated objects
        obj_version = util.get_json_value(obj, main_objecttype + '._version')
        if not isinstance(obj_version, int):
            continue
        if obj_version < 2:
            continue

        ids = set()
        obj_id = util.get_json_value(obj, main_objecttype + '._id')
        if isinstance(obj_id, int):
            ids.add(obj_id)
        elif isinstance(obj_id, list):
            # group edit mode
            group_edit = True
            for id in obj_id:
                if not isinstance(id, int):
                    continue
                ids.add(id)
        else:
            continue
        logger.info('{0} edit mode: {1} {2} object ids'.format(
            'group' if group_edit else 'single',
            len(ids),
            main_objecttype
        ))

        if iucnObjectsHandler.object_has_iucn_tags(obj, [tag_red, tag_unclear], group_edit):
            objects_with_iucn_tags.update(ids)
            continue

        objects_without_iucn_tags.update(ids)

    logger.debug('objects with iucn tags: [{0}]'.format(
        ','.join(map(lambda i: str(i), objects_with_iucn_tags))))
    logger.debug('objects without iucn tags: [{0}]'.format(
        ','.join(map(lambda i: str(i), objects_without_iucn_tags))))

    objects_move_nonpublic_to_public = set()
    objects_move_public_to_nonpublic = set()

    if len(objects_with_iucn_tags) > 0 or len(objects_without_iucn_tags) > 0:
        # search all of these objects that have one of the iucn tags before update
        search_result = iucnObjectsHandler.do_search(
            {
                'format': 'short',
                'objecttypes': [
                    main_objecttype
                ],
                'search': [
                    {
                        'bool': 'must',
                        'type': 'in',
                        'fields': [
                            main_objecttype + '._id'
                        ],
                        'in': list(objects_with_iucn_tags) + list(objects_without_iucn_tags)
                    }
                ]
            },
            limit=6  # xxx
        )

        # iterate over the objects in the search result
        # for each object there are 4 possible combinations:
        # 1.    object had no iucn tags before, also has no iucn tags now -> do nothing
        # 2.    object had no iucn tags before, but has iucn tags now -> move all links from 'Media Asset Non-Public' to 'Media Asset Public'
        # 3.    object had iucn tags before, also has iucn tags now -> do nothing
        # 4.    object had iucn tags before, but has no iucn tags now -> move all links from 'Media Asset Public' to 'Media Asset Non-Public'
        for obj in search_result:
            obj_id = util.get_json_value(obj, main_objecttype + '._id')
            if not isinstance(obj_id, int):
                continue

            has_iucn_tags = iucnObjectsHandler.object_has_iucn_tags(
                obj, [tag_red, tag_unclear])
            logger.debug('search result: {0} object {1} | has iucn tag: {2}'.format(
                main_objecttype,
                obj_id,
                'yes' if has_iucn_tags else 'no'
            ))

            if obj_id in objects_without_iucn_tags:
                logger.debug('search result: {0} object {1} | is in objects_without_iucn_tags'.format(
                    main_objecttype,
                    obj_id
                ))
                if has_iucn_tags:
                    # object had no iucn tags before, but has iucn tags now
                    # -> move all links from 'Media Asset Non-Public' to 'Media Asset Public'
                    objects_move_nonpublic_to_public.add(obj_id)
                    logger.debug('search result: {0} object {1} | add id to objects_move_nonpublic_to_public'.format(
                        main_objecttype,
                        obj_id
                    ))
            else:
                logger.debug('search result: {0} object {1} | is not in objects_without_iucn_tags'.format(
                    main_objecttype,
                    obj_id
                ))
                if not has_iucn_tags:
                    # object had iucn tags before, but has no iucn tags now
                    # -> move all links from 'Media Asset Public' to 'Media Asset Non-Public'
                    objects_move_public_to_nonpublic.add(obj_id)
                    logger.debug('search result: {0} object {1} | add id to objects_move_public_to_nonpublic'.format(
                        main_objecttype,
                        obj_id
                    ))

    # mediaassetpublic_links_by_object = {}
    # mediaassetnonpublic_links_by_object = {}
    # new_link_objects = {}

    # array_mediaassetpublic = '_reverse_nested:{0}_{1}:{0}'.format(
    #     main_objecttype, MEDIAASSETPUBLIC)
    # array_mediaassetnonpublic = '_reverse_nested:{0}_{1}:{0}'.format(
    #     main_objecttype, MEDIAASSETNONPUBLIC)

    if len(objects_move_nonpublic_to_public) + len(objects_move_public_to_nonpublic) > 0:
        iucnObjectsHandler.load_objecttype_ids([
            '{0}_{1}'.format(main_objecttype, MEDIAASSETPUBLIC),
            '{0}_{1}'.format(main_objecttype, MEDIAASSETNONPUBLIC)
        ])

    if len(objects_move_nonpublic_to_public) > 0:
        logger.info('objects to move from "Media Asset Non-Public" to "Media Asset Public": [{0}]'.format(
            ','.join(map(lambda i: str(i), objects_move_nonpublic_to_public))))

        # search for all <main_objecttype>_mediaassetnonpublic objects that are linked to any of these objects
        mediaasset_links_by_object, mediaassetlink_objects_to_delete = iucnObjectsHandler.collect_mediaasset_objects(
            main_objecttype,
            MEDIAASSETNONPUBLIC,
            objects_move_nonpublic_to_public
        )
        # create new <main_objecttype>_mediaassetpublic objects
        iucnObjectsHandler.insert_new_mediaasset_objects(
            main_objecttype,
            MEDIAASSETPUBLIC,
            mediaasset_links_by_object
        )
        # for k in new_objects:
        #     new_link_objects[k] = new_objects[k]

        if len(mediaassetlink_objects_to_delete) > 0:
            # delete and reindex all irrelevant media asset link objects from mediaassetlink_objects_to_delete
            iucnObjectsHandler.delete_old_mediaasset_link_objects(
                main_objecttype,
                MEDIAASSETNONPUBLIC,
                mediaassetlink_objects_to_delete
            )

    if len(objects_move_public_to_nonpublic) > 0:
        logger.info('objects to move from "Media Asset Public" to "Media Asset Non-Public": [{0}]'.format(
            ','.join(map(lambda i: str(i), objects_move_public_to_nonpublic))))

        # search for all <main_objecttype>_mediaassetpublic objects that are linked to any of these objects
        mediaasset_links_by_object, mediaassetlink_objects_to_delete = iucnObjectsHandler.collect_mediaasset_objects(
            main_objecttype,
            MEDIAASSETPUBLIC,
            objects_move_public_to_nonpublic
        )
        # create new <main_objecttype>_mediaassetnonpublic objects
        iucnObjectsHandler.insert_new_mediaasset_objects(
            main_objecttype,
            MEDIAASSETNONPUBLIC,
            mediaasset_links_by_object
        )
        # for k in new_objects:
        #     new_link_objects[k] = new_objects[k]

        if len(mediaassetlink_objects_to_delete) > 0:
            # delete and reindex all irrelevant media asset link objects from mediaassetlink_objects_to_delete
            iucnObjectsHandler.delete_old_mediaasset_link_objects(
                main_objecttype,
                MEDIAASSETPUBLIC,
                mediaassetlink_objects_to_delete
            )

    # response = []
    # for obj in data:
    #     # obj_id = util.get_json_value(obj, main_objecttype + '._id')

    #     # if obj_id in objects_move_public_to_nonpublic:
    #     #     if not array_mediaassetpublic in obj[main_objecttype]:
    #     #         response.append(obj)
    #     #         continue
    #     #     obj[main_objecttype][array_mediaassetnonpublic] = iucnObjectsHandler.move_mediaasset_links(
    #     #         main_objecttype,
    #     #         obj[main_objecttype][array_mediaassetpublic],
    #     #         new_link_objects,
    #     #         MEDIAASSETPUBLIC,
    #     #         MEDIAASSETNONPUBLIC,
    #     #     )
    #     #     obj[main_objecttype][array_mediaassetpublic] = []
    #     #     response.append(obj)
    #     #     continue

    #     # if obj_id in objects_move_nonpublic_to_public:
    #     #     if not array_mediaassetnonpublic in obj[main_objecttype]:
    #     #         response.append(obj)
    #     #         continue
    #     #     obj[main_objecttype][array_mediaassetpublic] = iucnObjectsHandler.move_mediaasset_links(
    #     #         main_objecttype,
    #     #         obj[main_objecttype][array_mediaassetnonpublic],
    #     #         new_link_objects,
    #     #         MEDIAASSETNONPUBLIC,
    #     #         MEDIAASSETPUBLIC,
    #     #     )
    #     #     obj[main_objecttype][array_mediaassetnonpublic] = []
    #     #     response.append(obj)
    #     #     continue

    #     # xxx

    #     # obj[main_objecttype][array_mediaassetpublic]=[]
    #     # obj[main_objecttype][array_mediaassetnonpublic]=[]

    #     response.append(obj)

    # todo create collections

    logger.debug('response: {0}'.format(util.dumpjs(data)))
    return data
