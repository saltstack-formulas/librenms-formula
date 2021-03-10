{% from "librenms/map.jinja" import librenms with context %}

include:
  - librenms

librenms_build_base:
  cmd.run:
    - cwd: {{ librenms.general.app_dir }}
    - runas: {{ librenms.general.user }}
    - name: php {{ librenms.general.app_dir }}/includes/sql-schema/update.php && php {{ librenms.general.app_dir }}/validate.php
    - require:
      - file: librenms_config
    - onchanges:
      - git: librenms_git
      - cmd: librenms_compose_install
