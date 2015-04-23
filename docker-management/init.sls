{% if 'docker' in pillar %}
{%- for name, entry in pillar['docker'].iteritems() -%}
{%- if entry.build -%}

#
# DOCKER BUILD PROCESS
#


# force rebuild by removing the current existing TEST tag
# note that this allows the docker.running state to continue successfully in case the forced build fails
{% if salt['pillar.get']('docker_force_build', False) == True %}
{{ name }}-rebuild:
  cmd.run:
    - name: docker rmi {{ entry.registry }}/{{ name }}:{{ entry.tag_test }}
{% endif %}

# fetch the directory caintaining the Dockerfile from the file server
{{ name }}-dockerfile:
  file.recurse:
    - name: /data/docker/{{ name }}
    - source: salt://docker/{{ name }}
    - clean: False
    - dir_mode: "0700"
    {%- if "template" in entry %}
    - template: {{ entry.template }}
    - defaults:
        name: {{ name }}
        data: {{ entry }}
    {% endif %}
    - include_empty: True

# add secret files from pillar data
{% if 'files' in entry %}
{% for file_name, file_data in entry.files.iteritems() %}
/data/docker/{{ name }}/{{ file_name }}:
  file.managed:
    - user: {{ file_data['user'] }}
    - group: {{ file_data['group'] }}
    - mode: {{ file_data['mode'] }}
    - contents_pillar: docker:{{ name }}:files:{{ file_name }}:contents
    - require:
      - file: {{ name }}-dockerfile
    - watch_in:
      - docker: {{ name }}-image
{% endfor %}
{% endif %}

# build the docker image
{{ name }}-image:
  docker.built:
    - name: {{ entry.registry }}/{{ name }}:{{ entry.tag_test }}
    - path: /data/docker/{{ name }}
    - nocache: {{ entry.nocache }}
    - rm: {{ entry.rm }}
    - quiet: {{ entry.quiet }}
    - watch:
      - file: {{ name }}-dockerfile
    {% if 'environment' in entry %}
    - environment: {{ entry.environment }}
    {% endif %}
    {%- if "build_requirements" in entry %}
    - require:
      {% for r in entry.build_requirements %}- cmd: {{ r }}-tag-current{% endfor %}
    {% endif %}


# test the docker image
{% if 'test_cmd' in entry %}
{{ name }}-test-run:
  cmd.run:
    - name: >
        docker run --rm --name={{ name }}-{{ entry.tag_test }}
        --hostname={% if 'hostname' in entry %}{{ entry.hostname }} {% else %}{{ name }}.{{ grains['id'] }} {% endif %}
        {%- if "volumes" in entry -%}{% for source, target in entry.volumes.iteritems() %}--volume={{ source }}:{{ target }} {% endfor %}{%- endif -%}
        {{ entry.registry }}/{{ name }}:{{ entry.tag_test }}
        {{ entry.test_cmd }}
    - require:
      - docker: {{ name }}-image
      {% if "run_requirements" in entry %}{% for r in entry.run_requirements %}
      - docker: {{ r }}
      {% endfor %}{% endif %}
    - unless: docker images --no-trunc | grep -e '{{ entry.registry }}/{{ name }}\s*{{ entry.tag_test }}' | awk '{ print $3 }' | grep $(docker images --no-trunc | grep -e '{{ entry.registry }}/{{ name }}\s*{{ entry.tag_latest }}' | awk '{ print $3 }')
# remove the test run container if it was successfull. Leave it for further inspection if it fails.
{{ name }}-test-destroy:
  docker.absent:
    - name: {{ name }}-{{ entry.tag_test }}
    - require:
      - cmd: {{ name }}-test-run
{% endif %}

# if the test run was successfull, tag the currently running image
{{ name }}-tag-previous:
  cmd.run:
    - name: docker tag -f {{ entry.registry }}/{{ name }}:{{ entry.tag_latest }} {{ entry.registry }}/{{ name }}:{{ entry.tag_previous }}
    - onlyif:
      - docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ entry.registry }}/{{ name }}:{{ entry.tag_latest }}
    - onchanges:
      {% if 'test_cmd' in entry %}
      - cmd: {{ name }}-test-run
      {% else %}
      - docker: {{ name }}-image
      {% endif %}

# tag the successfully tested image as current one. Update automagic will everything else.
{{ name }}-tag-current:
  cmd.run:
    - name: docker tag -f {{ entry.registry }}/{{ name }}:{{ entry.tag_test }} {{ entry.registry }}/{{ name }}:{{ entry.tag_latest }}
    - onchanges:
      {% if 'test_cmd' in entry %}
      - cmd: {{ name }}-test-run
      {% else %}
      - docker: {{ name }}-image
      {% endif %}
    - require:
      - cmd: {{ name }}-tag-previous
{% endif %}
#
# END OF THE BUILD PROCESS
#
{% endfor %}


{%- for name, entry in pillar['docker'].iteritems() -%}
#
# MANAGE DOCKER CONTAINERS
#
{% if 'run' in entry and entry.run %}
# TODO: from salt v2015.2 on switch from cmd.run to docker.absent.
{{ name }}-destroy-if-old:
  cmd.run:
    - name: docker stop {{ name }}; sleep 4 ; docker rm -f {{ name }}
    - onlyif:
      - docker inspect --format '{% raw %}{{ .Image }}{% endraw %}' {{ name }} | grep $(docker images --no-trunc | grep -e "{{ entry.registry }}/{{ name }}\s*{{ entry.tag_latest }}" | awk '{ print $3 }') && return 1 || return 0
      - docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ name }})
      - docker images --no-trunc | grep -e '{{ entry.registry }}/{{ name }}\s*{{ entry.tag_latest }}'
    {% if entry.build %}
    - require:
      - cmd: {{ name }}-tag-current
    {% endif %}

{% if "run_requirements" in entry %}
# TODO: from salt v2015.2 on switch from cmd.run to docker.absent.
{{ name }}-destroy-if-depedency-restarts:
  cmd.run:
    - name: docker stop {{ name }}; sleep 4 ; docker rm -f {{ name }}
    - onchanges:
      {% for r in entry.run_requirements %}
      - docker: {{ r }}
      {% endfor %}
    - onlyif:
      - docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ name }})
{% endif %}

#
# Remove container that lost their links due to the replacement of linked containers.
#
{% if 'links' in entry %}
{% for from, to in entry.links.items() %}
{{ name }}-link-{{ from }}-{{ to }}:
  cmd.run:
    - name: docker stop {{ name }}; sleep 4 ; docker rm -f {{ name }}
    - onlyif:
      - docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ name }})
    - unless:
      - docker inspect --format='{% raw %}{{ .HostConfig.Links }}{% endraw %}' {{ name }} | grep '/{{ from }}:/{{ name }}/{{ to }}'
    - require_in:
      - docker: {{ name }}-install
{% endfor %}
{% endif %}

# TODO: from salt v2015.2 on switch this to one state based on docker.running instead of combining .installed with .running.
#
# install the image
#
{{ name }}-install:
  docker.installed:
    - name: {{ name }}
    - hostname: {% if 'hostname' in entry %}{{ entry.hostname }}{% else %}{{ name }}.{{ grains['id'] }}{% endif %}
    - image: {{ entry.registry }}/{{ name }}:{{ entry.tag_latest }}
    {%- if "port_bindings" in entry %}
    - ports: {{ entry.port_bindings }}
    {% endif %}
    - onlyif:
      - docker images --no-trunc | grep -e '{{ entry.registry }}/{{ name }}\s*{{ entry.tag_latest }}'
    - require:
      - cmd: {{ name }}-destroy-if-old
      {% if entry.build %}
      - docker: {{ name }}-image
      {% endif %}
      {% if "run_requirements" in entry %}
      - cmd: {{ name }}-destroy-if-depedency-restarts
      {% for r in entry.run_requirements %}
      - docker: {{ r }}
      {% endfor %}{% endif %}

{{ name }}:
  docker.running:
    - name: {{ name }}
    - restart_policy:
        Name: always
        MaximumRetryCount: 0
    {%- if "port_bindings" in entry %}
    - port_bindings: {{ entry.port_bindings }}
    {% endif %}
    - require:
      - docker: {{ name }}-install
      {% if "run_requirements" in entry %}{% for r in entry.run_requirements %}
      - docker: {{ r }}
      {% endfor %}{% endif %}
    {%- if "links" in entry %}
    - links: {{ entry.links }}
    {%- endif %}
    {%- if "volumes" in entry %}
    # TODO: from salt v2015.2 on 'binds' will be renamed to 'volumes'
    - binds: {{ entry.volumes }}
    {% endif %}
    {%- if "volumes_from" in entry %}
    - volumes_from: {{ entry.volumes_from }}
    {% endif %}

{% elif not ('keep' in entry and entry.keep) %}

# TODO: from docker v2015.2 on switch from cmd.run to docker.absent.
{{ name }}-destroy:
  cmd.run:
    - name: docker stop {{ name }}; sleep 4 ; docker rm -f {{ name }}
    - onlyif: docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ name }})

{% endif %}

{% if 'src_ip' in entry %}
{% set comment = 'Salt: src_ip for ' ~ name %}

{{ name }}-remove-nat-wrong-host-ip:
  cmd.run:
    - name: "iptables -t nat -D POSTROUTING $(iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}' | awk '{ print $1 }')"
    # ONLY IF the rule exists AND src_ip differs from container_ip.
    - onlyif:
      - "iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}'"
      - "test $(iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}' | awk '{ print $5 }') != $(docker inspect --format='{% raw %}{{ .NetworkSettings.IPAddress }}{% endraw %}' {{ name }})"

{{ name }}-remove-nat-wrong-src-ip:
  cmd.run:
    - name: "iptables -t nat -D POSTROUTING $(iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}' | awk '{ print $1 }')"
    # ONLY IF the rule already exists AND the rules source_ip differs from pillars src_ip.
    - onlyif:
      - "iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}'"
      - "test $(sudo iptables -t nat -L POSTROUTING -n --line-numbers | grep '{{ comment }}' | sed 's/\\/\\*.*\\*\\///' | awk '{ print $7 }' | sed 's/to://') != {{ entry.src_ip }}"

{{ name }}-add-nat:
  cmd.run:
    - name: "iptables -t nat -I POSTROUTING -s $(docker inspect --format='{% raw %}{{ .NetworkSettings.IPAddress }}{% endraw %}' {{ name }}) -j SNAT --to-source {{ entry.src_ip }} -m comment --comment '{{ comment }}'"
    - onlyif:
      # ONLY IF the container already exists AND there is no entry for its IP yet.
      - "iptables -t nat -L POSTROUTING -n --line-numbers | grep $(docker inspect --format='{% raw %}{{ .NetworkSettings.IPAddress }}{% endraw %}' {{ name }}) && return 1 || return 0"
      - "docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' {{ name }})"
    - require:
      - docker: {{ name }}
      - cmd: {{ name }}-remove-nat-wrong-host-ip
      - cmd: {{ name }}-remove-nat-wrong-src-ip
{% endif %}
#
# TODO: remove NAT rules for all containers without src_ip. Requires at least to move the { comment } declaration. This is a requirement für { name }-add-nat: - cmd: { name }-remove-nat-no-container
#
#{ name }-remove-nat-no-container:
#  cmd.run:
#    - name: "iptables -t nat -D POSTROUTING $(iptables -t nat -L POSTROUTING -n --line-numbers | grep '{ comment }' | awk '{ print $1 }')"
#    - onlyif:
#      # NUR WENN die Regel existiert UND der container NICHT existiert.
#      - "iptables -t nat -L POSTROUTING -n --line-numbers | grep '{ comment }'"
#      - "docker ps -a -q --no-trunc | grep $(docker inspect --format='{% raw %}{{ .Id }}{% endraw %}' { name }) && return 1 || return 0"

{% endfor %}
{% endif %}
