# coding=utf8

from fylr_lib_plugin_python3 import util


class IucnObjectHandler(object):

    def __init__(self, easydb_context, logger_name, user_id) -> None:
        self.easydb_context = easydb_context
        self.db_cursor = easydb_context.get_db_cursor()
        self.logger = easydb_context.get_logger(logger_name)
        self.user_id = user_id
        self.objecttype_ids = {}

    @util.handle_exceptions
    def do_search(self, search_query, limit=0):
        # set optional limit if given
        if limit > 0:
            search_query['limit'] = limit

        self.logger.debug('search query (initial search): ' +
                          util.dumpjs(search_query))

        # perform first search, check if further searches with offset are necessary
        search_result = self.easydb_context.search(
            'user', self.user_id, search_query)
        count = util.get_json_value(search_result, 'count')
        if not isinstance(count, int):
            return []
        limit = util.get_json_value(search_result, 'limit')
        if not isinstance(limit, int):
            return []

        objects = util.get_json_value(search_result, 'objects')
        # self.logger.debug('search result (initial search): {0}/{1} objects: {2}'.format(
        #     len(objects),
        #     count,
        #     util.dumpjs(objects),
        # ))
        self.logger.debug('search result (initial search): {0}/{1} objects'.format(
            len(objects),
            count,
        ))

        if not isinstance(objects, list):
            return []
        if len(objects) >= count:
            # all objects in search result, no further searches necessary
            return objects

        offset = len(objects)
        has_more = True
        while has_more:
            search_query['offset'] = offset
            offset += limit
            self.logger.debug('search query (paged search): ' +
                              util.dumpjs(search_query))

            search_result = self.easydb_context.search(
                'user', self.user_id, search_query)
            new_objects = util.get_json_value(search_result, 'objects')
            # self.logger.debug('search result (paged search): {0}/{1} objects: {2}'.format(
            #     len(new_objects),
            #     count,
            #     util.dumpjs(new_objects),
            # ))
            self.logger.debug('search result (paged search): {0}/{1} objects'.format(
                len(new_objects),
                count,
            ))

            if not isinstance(new_objects, list):
                has_more = False
                continue

            objects += new_objects
            has_more = len(objects) < count

        return objects

    @util.handle_exceptions
    def delete_old_mediaasset_link_objects(self, main_objecttype, link_object_suffix, affected_link_objects):
        if len(affected_link_objects) < 1:
            return

        objecttype = "{0}_{1}".format(main_objecttype, link_object_suffix)
        ids = ','.join(map(lambda x: str(x), affected_link_objects))

        self.logger.info('delete {0} objects: [{1}]'.format(objecttype, ids))

        # statement = """
        #     UPDATE "{objecttype}"
        #     SET "{main_link}" = NULL,
        #         "{mediaasset_link}" = NULL,
        #         ":version" = ":version" + 1
        #     WHERE "id:pkey" = ANY('{ids}'::bigint[])

        statement = """
            DELETE FROM "{objecttype}"
            WHERE "id:pkey" = ANY('{ids}'::bigint[])
        """.format(
            objecttype=objecttype,
            # main_link=main_objecttype,
            # mediaasset_link=link_object_suffix,
            ids='{' + ids + '}'
        )
        self.logger.debug('DELETE statement for {0} objects: {1}'.format(
            objecttype,
            statement
        ))
        self.db_cursor.execute(statement)

        # delete index job (XXX: missing in easydb_context)
        self.insert_index_jobs('DELETE', objecttype, affected_link_objects)

    @util.handle_exceptions
    def insert_index_jobs(self, operation, objecttype, obj_ids):
        for obj_id in obj_ids:
            statement = """
                INSERT INTO ez_object_job (
                    type, operation, "ez_objecttype:id", ez_object_id, priority, insert_time)
                VALUES ('dirty', '{operation}'::op_row, {ot_id}, {obj_id}, 100, NOW())
            """.format(
                operation=operation,
                ot_id=self.objecttype_ids[objecttype],
                obj_id=obj_id
            )
            self.logger.debug('index job statement: {0}'.format(statement))
            self.db_cursor.execute(statement)

    # @util.handle_exceptions
    # def move_mediaasset_links(self, main_objecttype, array, new_link_objects, source, target):
    #     self.logger.debug('[move_mediaasset_links] ' + util.dumpjs(array) +
    #                       ' move from ' + source + ' to ' + target)

    #     if not isinstance(array, list):
    #         return []
    #     if len(array) < 1:
    #         return []

    #     objecttype = "{0}_{1}".format(main_objecttype, target)
    #     self.logger.debug('[move_mediaasset_links] objecttype:' + objecttype)
    #     self.logger.debug(
    #         '[move_mediaasset_links] new_link_objects:' + util.dumpjs(new_link_objects))

    #     obj_id_map = new_link_objects[objecttype]
    #     if obj_id_map is None:
    #         raise Exception(objecttype + ' not in map')
    #         # return [] # xxx

    #     moved = []
    #     for entry in array:
    #         if not source in entry:
    #             continue

    #         new_entry = {}
    #         for k in entry:
    #             if k == source:
    #                 new_entry[target] = entry[k]
    #                 continue

    #         new_entry['_objecttype'] = objecttype
    #         new_entry['_id'] = int(util.get_json_value(obj_id_map,
    #                                                    str(util.get_json_value(entry, source + '.mediaasset._id'))))
    #         new_entry['_version'] = 1

    #         moved.append(new_entry)

    #     self.logger.debug(
    #         '[move_mediaasset_links] ==> moved mediaassets: ' + util.dumpjs(moved))

    #     return moved

    @util.handle_exceptions
    def object_has_iucn_tags(self, obj, tag_ids, group_edit=False):

        if group_edit:
            tag_mode = util.get_json_value(obj, '_tags:group_mode')
            if tag_mode not in ['tag_add', 'tag_replace']:
                return False

        tags = util.get_json_value(obj, '_tags')
        if not isinstance(tags, list):
            return False

        for t in tags:
            tag_id = util.get_json_value(t, '_id')
            if tag_id in tag_ids:
                return True

        return False

    # @util.handle_exceptions
    # def create_reverse_nested_table(self, mediaassetlinks, link_object_suffix):
    #     nested = []

    #     self.logger.debug('create_reverse_nested_table: {0}: {1}'.format(
    #         link_object_suffix,
    #         util.dumpjs(mediaassetlinks)
    #     ))

    #     for main_object_id in mediaassetlinks:
    #         for mediaasset_id in mediaassetlinks[main_object_id]:
    #             new_obj = {
    #                 '_id': None,
    #                 '_version': 1,
    #                 link_object_suffix: {
    #                     'mediaasset': {
    #                         '_id': mediaasset_id
    #                     },
    #                     '_objecttype': 'mediaasset',
    #                     '_mask': '_all_fields'
    #                 }
    #             }
    #             nested.append(new_obj)

    #     return nested

    # @util.handle_exceptions
    # def find_mediaassetlink_objects(self, objecttype, main_objecttype, main_object_ids):
    #     return self.do_search(
    #         {
    #             'format': 'long',
    #             'objecttypes': [
    #                 objecttype
    #             ],
    #             'search': [
    #                 {
    #                     'bool': 'must',
    #                     'type': 'in',
    #                     'fields': [
    #                         objecttype + '.' + main_objecttype + '.' + main_objecttype + '._id'
    #                     ],
    #                     'in': list(main_object_ids)
    #                 }
    #             ]
    #         })

    @util.handle_exceptions
    def collect_mediaasset_objects(self, main_objecttype, link_object_suffix, main_object_ids):
        mediaassetlink_objecttype = main_objecttype + '_' + link_object_suffix

        # find all media asset link objects that are linked to any of the main objects
        search_result = self.do_search(
            {
                'format': 'long',
                'objecttypes': [
                    mediaassetlink_objecttype
                ],
                'search': [
                    {
                        'bool': 'must',
                        'type': 'in',
                        'fields': [
                            mediaassetlink_objecttype + '.' + main_objecttype + '.' + main_objecttype + '._id'
                        ],
                        'in': list(main_object_ids)
                    }
                ]
            })

        # iterate over the objects in the search result
        # for each object, collect all links to mediaasset objects
        links_by_object = {}
        objects_to_delete = set()

        for obj in search_result:
            obj_id = util.get_json_value(
                obj, mediaassetlink_objecttype + '._id')
            if not isinstance(obj_id, int):
                continue

            main_obj_id = util.get_json_value(
                obj,
                '{0}.{1}.{1}._id'.format(
                    mediaassetlink_objecttype,
                    main_objecttype
                ))
            if not isinstance(main_obj_id, int):
                continue

            objects_to_delete.add(obj_id)

            mediaasset_obj_id = util.get_json_value(
                obj,
                '{0}.{1}.mediaasset._id'.format(
                    mediaassetlink_objecttype,
                    link_object_suffix
                ))
            if not isinstance(mediaasset_obj_id, int):
                continue

            if not main_obj_id in links_by_object:
                links_by_object[main_obj_id] = []
            links_by_object[main_obj_id].append(mediaasset_obj_id)

        self.logger.debug('[collect_mediaasset_objects] mediaassetlinks for {0}: {1}'.format(
            mediaassetlink_objecttype,
            util.dumpjs(links_by_object)))

        return links_by_object, list(objects_to_delete)

    @util.handle_exceptions
    def insert_new_mediaasset_objects(self, main_objecttype, link_object_suffix, mediaassetlinks):
        mediaassetlink_objecttype = main_objecttype + '_' + link_object_suffix

        self.logger.debug('mediaassetlinks for {0}: {1}'.format(
            link_object_suffix,
            util.dumpjs(mediaassetlinks)))

        values = set()
        index_jobs = {
            main_objecttype: set(),
            'mediaasset': set(),
            mediaassetlink_objecttype: set(),
        }

        for main_object_id in mediaassetlinks:
            index_jobs[main_objecttype].add(main_object_id)
            for mediaasset_id in mediaassetlinks[main_object_id]:
                index_jobs['mediaasset'].add(mediaasset_id)
                values.add((main_object_id, mediaasset_id, self.user_id))

        # insert new objects
        if len(values) > 0:
            statement = """
                INSERT INTO "{table}"
                ("{main_objecttype}", "{link_object_suffix}", ":owner:ez_user:id")
                VALUES {values}
                RETURNING "id:pkey", "{main_objecttype}", "{link_object_suffix}";
            """.format(
                table=mediaassetlink_objecttype,
                main_objecttype=main_objecttype,
                link_object_suffix=link_object_suffix,
                values=','.join(map(
                    lambda v: '({0}, {1}, {2})'.format(v[0], v[1], v[2]),
                    values
                ))
            )
            self.logger.debug('insert statement for {0} objects: {1}'.format(
                mediaassetlink_objecttype,
                statement
            ))

            # new_mediaasset_links = {
            #     mediaassetlink_objecttype: {}
            # }

            self.db_cursor.execute(statement)
            for row in self.db_cursor.fetchall():
                try:
                    index_jobs[mediaassetlink_objecttype].add(
                        int(util.get_json_value(row, 'id:pkey')))
                    # new_mediaasset_links[mediaassetlink_objecttype][util.get_json_value(
                    #     row, link_object_suffix)] = util.get_json_value(row, 'id:pkey')
                except Exception as e:
                    pass

            self.logger.info('created new {0} objects: [{1}]'.format(
                mediaassetlink_objecttype,
                ','.join(
                    map(lambda x: str(x), index_jobs[mediaassetlink_objecttype]))
            ))

        for objecttype in index_jobs:
            if len(index_jobs[objecttype]) < 1:
                continue
            self.easydb_context.update_user_objects(
                objecttype,
                list(index_jobs[objecttype]),
                True
            )
            self.logger.debug('UPDATE index jobs for {0} objects: [{1}]'.format(
                objecttype,
                ','.join(
                    map(lambda x: str(x), index_jobs[objecttype]))
            ))

        # return new_mediaasset_links

    @util.handle_exceptions
    def load_objecttype_ids(self, objecttypes):
        statement = """
            SELECT name, "ez_objecttype:id"
            FROM ez_objecttype
            WHERE name = ANY ('{objecttypes}'::text[])
        """.format(
            objecttypes='{' + ','.join(objecttypes) + '}'
        )
        self.logger.debug(
            'load objecttype ids statement: {0}'.format(statement))
        self.db_cursor.execute(statement)

        self.objecttype_ids = {}
        for r in self.db_cursor.fetchall():
            self.objecttype_ids[util.get_json_value(
                r, 'name')] = util.get_json_value(r, 'ez_objecttype:id')
