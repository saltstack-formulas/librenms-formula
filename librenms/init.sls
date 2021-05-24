{% from "librenms/map.jinja" import librenms with context %}

librenms_pkgs_install:
  pkg.installed:
    - names: {{ librenms.lookup.pkgs }}

librenms_directory:
  file.directory:
    - name: {{ librenms.general.app_dir }}
    - user: {{ librenms.general.user }}
    - group: {{ librenms.general.group }}
    - require:
      - user: librenms_user
      - group: librenms_user

librenms_git:
  git.latest:
    - name: https://github.com/librenms/librenms.git
    - user: {{ librenms.general.user }}
    - target: {{ librenms.general.app_dir }}
    - rev: {{ librenms.get('revision', 'master') }}
    - force_checkout: True
    - force_clone: True
    - force_fetch: True
    - force_reset: True
    - require:
      - pkg: librenms_pkgs_install
      - user: librenms_user
      - file: librenms_directory
    - unless: "LANG=C git status | grep -qv 'ahead\\|behind'"

{% if librenms.config.base_path is defined %}
{% set customfile = librenms.general.app_dir + "/html/plugins/custom-htaccess.conf" %}
librenms_remove_custom_htaccess_if_setting_changed:
  cmd.run:
    - name: rm -f {{ customfile }}
    - unless: grep -q "RewriteBase {{ librenms.config.base_path }}$" {{ customfile }} 
librenms_custom_htaccess:
  file.copy:
    # html/plugins/* is ignored by .gitignore
    - name: {{ customfile }}
    - source: {{ librenms.general.app_dir }}/html/.htaccess
    - force: true
    - require:
      - cmd: librenms_remove_custom_htaccess_if_setting_changed
    - onchanges:
      - git: librenms_git
      - cmd: librenms_remove_custom_htaccess_if_setting_changed
librenms_custom_rewrite_base:
  file.replace:
    - name: {{ customfile }}
    - pattern: 'RewriteBase .*$'
    - repl: "RewriteBase {{ librenms.config.base_path }}"
    - onchanges:
      - file: librenms_custom_htaccess
{% endif %}


librenms_config:
  file.managed:
    - name: {{ librenms.general.app_dir }}/config.php
    - source: salt://librenms/files/config.php
    - template: jinja
    - user: {{ librenms.general.user }}
    - group: {{ librenms.general.group }}
    - mode: 640
    - require:
      - file: librenms_directory

librenms_user:
  user.present:
    - name: {{ librenms.general.user }}
    - gid: {{ librenms.general.group }}
    - groups:
      - {{ librenms.lookup.webserver_group }}
    - createhome: False
    - shell: {{ librenms.lookup.nologin_shell}}
    - system: True
    - require:
      - group: librenms_user
  group.present:
    - name: {{ librenms.general.group }}
    - system: True
    - addusers:
      - {{ librenms.lookup.webserver_user }}

{% for subdir in ['bootstrap/cache', 'logs', 'rrd', 'storage'] %}
librenms_{{ subdir | replace('/', '_') }}_ownership:
  cmd.run:
    - name: chown -R {{ librenms.general.user }}:{{ librenms.general.group }}  {{ librenms.general.app_dir }}/{{ subdir }}
    - onchanges:
      - git: librenms_git
      - cmd: librenms_compose_install

librenms_{{ subdir | replace('/', '_') }}_permissions:
  cmd.run:
    - name: chmod -R ug=rwX,o=rX {{ librenms.general.app_dir }}/{{ subdir }}
    - onchanges:
      - git: librenms_git
      - cmd: librenms_compose_install

{%  if grains['os_family'] != 'FreeBSD' %}
librenms_{{ subdir | replace('/', '_') }}_acl:
  acl.present:
    - name: {{ librenms.general.app_dir }}/{{ subdir }}
    - acl_type: default:group
    - acl_name: {{ librenms.general.group }}
    - perms: rwx
    - require:
      - file: {{ librenms.general.app_dir }}/{{ subdir }}
      - git: librenms_git
      - cmd: librenms_compose_install
{%  endif %}
{% endfor %}

librenms_crontab:
{% if grains['os_family'] == 'FreeBSD' %}
{# FreeBSD has no /etc/cron.d/ and a uses slightly different format #}
  cmd.run:
    - name: "sed 's#  librenms    #  #g' '{{ librenms.general.app_dir }}/librenms.nonroot.cron' | sed 's#/opt/librenms#{{ librenms.general.app_dir }}#g' > /var/cron/tabs/librenms"
    - onchanges:
      - git: librenms_git
  file.managed:
    - name: /var/cron/tabs/librenms
    - mode: 600
    - user: root
    - group: wheel
    # prevent log message
    - replace: False
{% else %}
  file.managed:
    - name: /etc/cron.d/librenms
    - source: {{ librenms.general.app_dir }}/librenms.nonroot.cron
    - require:
      - git: librenms_git
{% endif %}

librenms_compose_install:
  cmd.run:
    - name: ./scripts/composer_wrapper.php install --no-dev || ( touch ./trigger_change_in_git_repo; false )
    - runas: {{ librenms.general.user }}
    - cwd: {{ librenms.general.app_dir }}
    - onchanges:
      - git: librenms_git
      - file: librenms_compose_trigger

librenms_compose_trigger:
  file.absent:
    - name: {{ librenms.general.app_dir }}/trigger_change_in_git_repo
